
Task { @MainActor in
    do {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let movie = directory.appendingPathComponent("source.mov")
        let writer = try AVAssetWriter(outputURL: movie, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 320, AVVideoHeightKey: 240])
        input.transform = CGAffineTransform(rotationAngle: .pi / 2)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 240])
        writer.add(input)
        precondition(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        for index in 0..<10 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(10)) }
            var buffer: CVPixelBuffer?
            CVPixelBufferCreate(kCFAllocatorDefault, 320, 240, kCVPixelFormatType_32BGRA, nil, &buffer)
            let pixel = buffer!
            CVPixelBufferLockBaseAddress(pixel, [])
            memset(CVPixelBufferGetBaseAddress(pixel), 128, CVPixelBufferGetDataSize(pixel))
            CVPixelBufferUnlockBaseAddress(pixel, [])
            precondition(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(index), timescale: 10)))
        }
        input.markAsFinished()
        await writer.finishWriting()
        precondition(writer.status == .completed)
        let captured = try await RoomPhotoCapture.capture(movieURL: movie, clipID: "source", propertyID: "property", seconds: 0.5)
        let capturedImage = UIImage(data: captured.jpeg)!
        precondition(capturedImage.size.height > capturedImage.size.width, "Source orientation lost")
        precondition(abs(captured.sourceSeconds - 0.5) < 0.11 && captured.clipID == "source" && captured.propertyID == "property")
        let withBearing = try await RoomPhotoCapture.capture(
            movieURL: movie, clipID: "source", propertyID: "property", seconds: 0.5,
            headings: [HeadingSample(seconds: 0, degrees: 90, accuracy: 5)]
        )
        let stamped = UIImage(data: withBearing.jpeg)!.cgImage!
        precondition(withBearing.jpeg != captured.jpeg, "A recorded bearing must change the JPEG compass")
        func brightness(x: Int, y: Int) -> Int {
            let pixel = stamped.cropping(to: CGRect(x: x, y: y, width: 1, height: 1))!
            var bytes: [UInt8] = [0, 0, 0, 0]
            bytes.withUnsafeMutableBytes { data in
                let context = CGContext(data: data.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return (Int(bytes[0]) + Int(bytes[1]) + Int(bytes[2])) / 3
        }
        let shortest = Double(min(stamped.width, stamped.height))
        let untouched = brightness(x: stamped.width - 10, y: stamped.height - 10)
        var shadedPixels = 0
        for column in 0..<7 {
            for row in 0..<7 {
                let x = Int(shortest * (0.07 + Double(column) * 0.02))
                let y = Int(shortest * (0.07 + Double(row) * 0.02))
                if brightness(x: x, y: y) + 35 < untouched { shadedPixels += 1 }
            }
        }
        precondition(shadedPixels >= 24, "Compass badge must be embedded in the upper-left JPEG pixels")
        let store = RoomPhotoStore(directory: directory)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let bounds = CGRect(x: 0, y: 0, width: 1200, height: 1800)
        let jpeg = UIGraphicsImageRenderer(size: bounds.size, format: format).image { context in
            UIColor.blue.setFill()
            context.fill(bounds)
        }.jpegData(compressionQuality: 0.8)!
        var card = RoomPhotoCard(id: UUID(), clipID: "clip-a", propertyID: "property-a", sourceSeconds: 12.5,
            created: Date(), updated: Date(), roomType: "Bedroom", name: "Bedroom 1", lengthMetres: nil,
            widthMetres: nil, heightMetres: nil, unit: .feet, notes: "Measured manually")
        card.sessionID = UUID()
        try await store.save(card, jpeg: jpeg)
        let copy = try await store.exportCopy(card.id)
        let copiedBytes = try Data(contentsOf: copy)
        precondition(copiedBytes == jpeg, "Photo sharing changed the original JPEG bytes")
        try FileManager.default.removeItem(at: copy)
        let originalBytes = try await store.image(card.id)
        precondition(originalBytes == jpeg, "Export cleanup removed the original photo")
        let thumbnail = try await store.thumbnail(card.id)
        precondition(thumbnail.height == 1024 && thumbnail.width < thumbnail.height,
                     "Gallery thumbnail exceeded its size limit or lost its portrait aspect")
        let reopened = RoomPhotoStore(directory: directory)
        let cards = try await reopened.all(clipID: "clip-a", propertyID: "property-a")
        precondition(cards.count == 1 && cards[0].id == card.id && cards[0].sourceSeconds == 12.5 && cards[0].roomID != nil, "Persistence or linkage failed")
        card = cards[0]
        let visitCards = try await reopened.all(sessionID: card.sessionID)
        let otherVisitCards = try await reopened.all(sessionID: UUID())
        precondition(visitCards.count == 1 && visitCards[0].sessionID == card.sessionID && otherVisitCards.isEmpty)
        let empty = try await reopened.all(propertyID: "other")
        precondition(empty.isEmpty)
        card.lengthMetres = 10 * RoomDimensionUnit.feet.factor
        card.widthMetres = 12 * RoomDimensionUnit.feet.factor
        card.name = "Main bedroom"
        try await reopened.save(card)
        let edited = try await store.all()
        let image = try await store.image(card.id)
        precondition(edited == [card] && edited[0].sessionID == card.sessionID && image == jpeg, "Editing lost photo or metadata")
        precondition(abs(card.lengthMetres! / RoomDimensionUnit.feet.factor - 10) < 0.000001)
        precondition(card.area != nil)
        var second = card
        second.id = UUID(); second.clipID = "clip-b"; second.sourceSeconds = 5
        try await store.save(second, jpeg: jpeg)
        var otherRoom = card; otherRoom.id = UUID(); otherRoom.roomID = UUID(); otherRoom.name = "Bedroom 2"
        try await store.save(otherRoom, jpeg: jpeg)
        var otherProperty = card; otherProperty.id = UUID(); otherProperty.roomID = nil; otherProperty.propertyID = "property-b"
        try await store.save(otherProperty, jpeg: jpeg)
        card.lengthMetres = 4; card.widthMetres = 5; card.notes = "Updated shared room"
        try await store.save(card)
        let shared = try await reopened.all()
        let linked = shared.first { $0.id == second.id }!
        precondition(linked.lengthMetres == 4 && linked.widthMetres == 5 && linked.notes == card.notes)
        precondition(linked.clipID == "clip-b" && linked.sourceSeconds == 5, "Sharing changed photo provenance")
        precondition(shared.first { $0.id == otherRoom.id }!.lengthMetres == otherRoom.lengthMetres)
        precondition(shared.first { $0.id == otherProperty.id }!.lengthMetres == otherProperty.lengthMetres)
        second = linked; second.roomID = otherRoom.roomID; second.name = otherRoom.name
        second.lengthMetres = otherRoom.lengthMetres; second.widthMetres = otherRoom.widthMetres
        try await store.save(second)
        let moved = try await reopened.all()
        precondition(moved.first { $0.id == card.id }!.lengthMetres == 4)
        for id in [second.id, otherRoom.id, otherProperty.id] { try await store.delete(id) }
        for value in [0.0, -1, Double.nan, Double.infinity] {
            var invalid = card; invalid.lengthMetres = value
            do { try invalid.validate(); fatalError("Invalid dimension accepted") }
            catch RoomPhotoError.invalidDetails {}
        }
        var invalid = card; invalid.widthMetres = nil
        do { try invalid.validate(); fatalError("Unpaired dimension accepted") }
        catch RoomPhotoError.invalidDetails {}
        try await reopened.delete(card.id)
        let remaining = try await store.all()
        precondition(remaining.isEmpty)
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(card.id.uuidString + ".jpg").path))
        let legacyDirectory = directory.appendingPathComponent("legacy")
        try FileManager.default.createDirectory(at: legacyDirectory, withIntermediateDirectories: true)
        var legacy1 = card; legacy1.roomID = nil; legacy1.updated = Date(timeIntervalSince1970: 1); legacy1.lengthMetres = 2
        var legacy2 = legacy1; legacy2.id = UUID(); legacy2.updated = Date(timeIntervalSince1970: 2); legacy2.lengthMetres = 6
        for legacy in [legacy1, legacy2] {
            try JSONEncoder().encode(legacy).write(to: legacyDirectory.appendingPathComponent(legacy.id.uuidString + ".json"))
            try jpeg.write(to: legacyDirectory.appendingPathComponent(legacy.id.uuidString + ".jpg"))
        }
        let migrated = try await RoomPhotoStore(directory: legacyDirectory).all()
        precondition(migrated.count == 2 && migrated.allSatisfy { $0.lengthMetres == 6 && $0.roomID == migrated[0].roomID })
        print("PASS: rotated video frame capture, timestamp and embedded compass; offline persistence, source/property links, dimension edits, retained photo, unit conversion, invalid dimensions, deletion, shared rooms, room/property isolation, reassignment and legacy migration")
        exit(0)
    } catch { print("FAIL: \(error)"); exit(1) }
}
dispatchMain()
