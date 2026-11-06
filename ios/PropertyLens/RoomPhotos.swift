import SwiftUI
import AVFoundation
import UIKit
import ImageIO

// Dimensions are human-supplied. Stored in metres, displayed in the chosen unit.
enum RoomDimensionUnit: String, Codable, CaseIterable, Sendable {
    case metres, feet
    var factor: Double { self == .feet ? 0.3048 : 1 }
    var label: String { self == .feet ? "Feet" : "Metres" }
    var symbol: String { self == .feet ? "ft" : "m" }
}

struct RoomPhotoCard: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var roomID: UUID? = nil
    var clipID: String
    var propertyID: String?
    var sourceSeconds: Double
    var created: Date
    var updated: Date
    var roomType: String
    var name: String
    var lengthMetres: Double?
    var widthMetres: Double?
    var heightMetres: Double?
    var unit: RoomDimensionUnit
    var notes: String
    var sessionID: UUID? = nil
    var dimensions: String {
        var parts: [String] = []
        if let lengthMetres, let widthMetres {
            parts.append("\(Self.number(lengthMetres / unit.factor)) × \(Self.number(widthMetres / unit.factor)) \(unit.symbol)")
        }
        if let heightMetres { parts.append("Height \(Self.number(heightMetres / unit.factor)) \(unit.symbol)") }
        return parts.isEmpty ? "Dimensions not added yet" : parts.joined(separator: " · ")
    }
    var area: String? {
        guard let lengthMetres, let widthMetres else { return nil }
        return "Rectangular area: \(Self.number(lengthMetres * widthMetres / (unit.factor * unit.factor))) \(unit.symbol)²"
    }
    static func number(_ value: Double) -> String { value.formatted(.number.grouping(.never).precision(.significantDigits(1...8))) }
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              sourceSeconds.isFinite, sourceSeconds >= 0,
              (lengthMetres == nil) == (widthMetres == nil),
              [lengthMetres, widthMetres, heightMetres].compactMap({ $0 }).allSatisfy({ $0.isFinite && $0 > 0 }),
              (lengthMetres ?? 1) * (widthMetres ?? 1) < Double.greatestFiniteMagnitude else {
            throw RoomPhotoError.invalidDetails
        }
    }
}

enum RoomPhotoError: LocalizedError {
    case invalidDetails, missingPhoto
    var errorDescription: String? {
        switch self {
        case .invalidDetails: "Enter a room name and positive dimensions. Add length and width together, or leave both empty."
        case .missingPhoto: "The room photo is missing. Capture another frame from the video."
        }
    }
}

actor RoomPhotoStore {
    static let shared = RoomPhotoStore()
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("RoomPhotos", isDirectory: true)
    }
    private func metadata(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func photo(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".jpg") }
    private var index: URL { directory.appendingPathComponent("rooms-v2.json") }
    private func key(_ card: RoomPhotoCard) -> String {
        let scope = card.propertyID.map { "property:" + $0 } ?? "video:" + card.clipID
        return scope + "|" + card.roomType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() + "|" + card.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
    private func write(_ cards: [RoomPhotoCard]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(cards).write(to: index, options: .atomic)
    }
    private func records() throws -> [RoomPhotoCard] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        if FileManager.default.fileExists(atPath: index.path) {
            return try JSONDecoder().decode([RoomPhotoCard].self, from: Data(contentsOf: index))
        }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        var groups: [String: UUID] = [:]
        var cards = try files.filter { $0.pathExtension == "json" }.map {
            try JSONDecoder().decode(RoomPhotoCard.self, from: Data(contentsOf: $0))
        }.sorted { $0.updated < $1.updated }
        for i in cards.indices {
            let group = key(cards[i])
            let id = groups[group] ?? UUID()
            groups[group] = id
            cards[i].roomID = id
        }
        // The most recently edited photo supplies the initial shared room details.
        var latestByRoom: [UUID: RoomPhotoCard] = [:]
        for card in cards {
            if let id = card.roomID { latestByRoom[id] = card }
        }
        for i in cards.indices {
            if let id = cards[i].roomID, let latest = latestByRoom[id] {
                copyDetails(latest, to: &cards[i])
            }
        }
        try write(cards)
        return cards
    }
    private func copyDetails(_ source: RoomPhotoCard, to target: inout RoomPhotoCard) {
        target.name = source.name; target.roomType = source.roomType
        target.lengthMetres = source.lengthMetres; target.widthMetres = source.widthMetres
        target.heightMetres = source.heightMetres; target.unit = source.unit
        target.notes = source.notes; target.updated = source.updated
    }
    func all(clipID: String? = nil, propertyID: String? = nil, sessionID: UUID? = nil) throws -> [RoomPhotoCard] {
        try records().filter { card in
            (clipID == nil || card.clipID == clipID) && (propertyID == nil || card.propertyID == propertyID) &&
            (sessionID == nil || card.sessionID == sessionID)
        }.sorted { $0.created > $1.created }
    }
    private let thumbnails: NSCache<NSUUID, CGImage> = {
        let cache = NSCache<NSUUID, CGImage>()
        cache.totalCostLimit = 24 * 1024 * 1024
        return cache
    }()

    func thumbnail(_ id: UUID) throws -> CGImage {
        try Task.checkCancellation()
        let key = id as NSUUID
        if let cached = thumbnails.object(forKey: key) { return cached }
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(photo(id) as CFURL, sourceOptions),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw RoomPhotoError.missingPhoto
        }
        thumbnails.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }

    func image(_ id: UUID) throws -> Data { try Data(contentsOf: photo(id)) }
    func save(_ value: RoomPhotoCard, jpeg: Data? = nil) throws {
        try value.validate()
        var cards = try records()
        var card = value
        let old = cards.first { $0.id == card.id }
        let match = cards.first { key($0) == key(card) && $0.roomType != "Uncategorised" }
        card.roomID = card.roomID ?? old?.roomID ?? match?.roomID ?? UUID()
        // Room IDs never bridge properties or unrelated unassigned videos.
        if let member = cards.first(where: { $0.roomID == card.roomID }) {
            guard member.propertyID == card.propertyID,
                  card.propertyID != nil || member.clipID == card.clipID else { throw RoomPhotoError.invalidDetails }
        }
        if old == nil, let match, card.lengthMetres == nil, card.widthMetres == nil {
            card.lengthMetres = match.lengthMetres; card.widthMetres = match.widthMetres
            card.heightMetres = card.heightMetres ?? match.heightMetres
            if card.notes.isEmpty { card.notes = match.notes }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if let jpeg {
            guard !jpeg.isEmpty else { throw RoomPhotoError.missingPhoto }
            try jpeg.write(to: photo(card.id), options: .atomic)
            thumbnails.removeObject(forKey: card.id as NSUUID)
        }
        guard FileManager.default.fileExists(atPath: photo(card.id).path) else { throw RoomPhotoError.missingPhoto }
        for i in cards.indices where cards[i].roomID == card.roomID { copyDetails(card, to: &cards[i]) }
        cards.removeAll { $0.id == card.id }
        cards.append(card)
        do { try write(cards) }
        catch {
            if old == nil { try? FileManager.default.removeItem(at: photo(card.id)) }
            throw error
        }
    }
    func delete(_ id: UUID) throws {
        var cards = try records()
        cards.removeAll { $0.id == id }
        try write(cards)
        thumbnails.removeObject(forKey: id as NSUUID)
        try? FileManager.default.removeItem(at: photo(id))
        try? FileManager.default.removeItem(at: metadata(id))
    }
}

struct CapturedRoomPhoto: Identifiable, Sendable {
    let id = UUID()
    let clipID: String
    let propertyID: String?
    let sourceSeconds: Double
    let jpeg: Data
    var sessionID: UUID? = nil
}

enum RoomPhotoCapture {
    @MainActor static func capture(_ clip: Walkthrough, seconds: Double) async throws -> CapturedRoomPhoto {
        try await capture(movieURL: clip.movie, clipID: clip.id, propertyID: clip.propertyID, seconds: seconds, sessionID: clip.sessionID, headings: clip.headings)
    }
    @MainActor static func capture(movieURL: URL, clipID: String, propertyID: String?, seconds: Double, sessionID: UUID? = nil, headings: [HeadingSample] = []) async throws -> CapturedRoomPhoto {
        let asset = AVURLAsset(url: movieURL)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw RoomPhotoError.missingPhoto }
        let requested = min(max(seconds.isFinite ? seconds : 0, 0), max(0, duration - 1.0 / 30))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1600, height: 1600)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.1, preferredTimescale: 600)
        let frame = try await generator.image(at: CMTime(seconds: requested, preferredTimescale: 600))
        try Task.checkCancellation()
        let time = max(0, frame.actualTime.seconds)
        let sample = headings.last { $0.seconds <= time }
        let bearing = sample.flatMap { time - $0.seconds < 5 ? $0.degrees : nil }
        let source = frame.image
        let data = try await Task.detached(priority: .userInitiated) {
            try compassJPEG(UIImage(cgImage: source), bearing: bearing)
        }.value
        try Task.checkCancellation()
        return CapturedRoomPhoto(clipID: clipID, propertyID: propertyID, sourceSeconds: time, jpeg: data, sessionID: sessionID)
    }

    static func compassJPEG(_ image: UIImage, bearing: Double?) throws -> Data {
        let size = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard size.width > 0, size.height > 0 else { throw RoomPhotoError.missingPhoto }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let dial = CompassDialArtwork.image(bearing: bearing.flatMap { $0.isFinite && (0..<360).contains($0) ? $0 : nil })
        let shortestSide = min(size.width, size.height)
        let badgeWidth = shortestSide * 0.18
        let inset = shortestSide * 0.04
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
            dial.draw(in: CGRect(x: inset, y: inset, width: badgeWidth, height: badgeWidth * 196 / 160))
        }
        guard let jpeg = rendered.jpegData(compressionQuality: 0.92) else { throw RoomPhotoError.missingPhoto }
        return jpeg
    }
}

struct RoomPhotoImage: View {
    let id: UUID
    @State private var image: CGImage?
    @State private var unavailable = false
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .tertiarySystemGroupedBackground)
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable().scaledToFit()
                        .frame(width: geometry.size.width, height: geometry.size.height)
                } else if unavailable {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.secondary)
                        .accessibilityLabel("Photo unavailable")
                } else {
                    ProgressView().accessibilityLabel("Loading photo")
                }
            }
        }
        .frame(height: 220)
        .task(id: id) {
            image = nil
            unavailable = false
            do {
                let thumbnail = try await RoomPhotoStore.shared.thumbnail(id)
                try Task.checkCancellation()
                image = thumbnail
            } catch is CancellationError {
                return
            } catch {
                if !Task.isCancelled { unavailable = true }
            }
        }
    }
}

private struct FullScreenRoomPhoto: View {
    enum Source {
        case saved(UUID)
        case captured(Data)
    }

    let title: String
    let source: Source
    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var unavailable = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .accessibilityLabel(title)
                } else if unavailable {
                    ContentUnavailableView("Photo unavailable", systemImage: "photo")
                } else {
                    ProgressView("Loading photo")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.65), in: Circle())
            }
            .accessibilityLabel("Close photo")
            .padding(12)
        }
        .preferredColorScheme(.dark)
        .foregroundStyle(.white)
        .task {
            do {
                let data: Data
                switch source {
                case .saved(let id): data = try await RoomPhotoStore.shared.image(id)
                case .captured(let jpeg): data = jpeg
                }
                try Task.checkCancellation()
                image = UIImage(data: data)
                unavailable = image == nil
            } catch {
                if !Task.isCancelled { unavailable = true }
            }
        }
    }
}

private struct RoomPhotoPreviewButton<Preview: View>: View {
    let title: String
    let open: () -> Void
    @ViewBuilder var preview: () -> Preview

    var body: some View {
        Button(action: open) {
            preview()
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.caption.weight(.semibold))
                        .padding(10)
                        .background(.black.opacity(0.65), in: Circle())
                        .foregroundStyle(.white)
                        .padding(8)
                        .accessibilityHidden(true)
                }
                .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("View \(title) full screen")
    }
}

struct RoomPhotoLibrary: View {
    var sessionID: UUID? = nil
    var clipID: String? = nil
    var propertyID: String? = nil
    @State private var cards: [RoomPhotoCard] = []
    @State private var loading = true
    @State private var edit: RoomPhotoCard?
    @State private var viewingPhoto: RoomPhotoCard?
    @State private var pendingDelete: RoomPhotoCard?
    @State private var error: String?
    private func reload() async {
        defer { loading = false }
        do { cards = try await RoomPhotoStore.shared.all(clipID: clipID, propertyID: propertyID, sessionID: sessionID) }
        catch { self.error = error.localizedDescription }
    }
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 20) {
                if loading {
                    ProgressView("Loading photos").frame(maxWidth: .infinity).padding(.vertical, 32)
                } else if cards.isEmpty && error == nil {
                    ContentUnavailableView("No room photos yet", systemImage: "photo.on.rectangle", description: Text("Tap Photo beside the video button, or capture a frame from a saved walkthrough. Add room details whenever you are ready."))
                }
                ForEach(cards) { card in
                    VStack(alignment: .leading, spacing: 12) {
                        RoomPhotoPreviewButton(title: card.name, open: { viewingPhoto = card }) {
                            RoomPhotoImage(id: card.id)
                        }
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name).font(.title3.bold())
                                Text(card.roomType).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Menu {
                                Button("View full screen", systemImage: "arrow.up.left.and.arrow.down.right") { viewingPhoto = card }
                                Button("Edit details", systemImage: "pencil") { edit = card }
                                Button("Delete room card", systemImage: "trash", role: .destructive) { pendingDelete = card }
                            } label: { Image(systemName: "ellipsis.circle").frame(width: 44, height: 44) }
                        }
                        Text(card.dimensions).font(.headline)
                        if let area = card.area { Text(area).font(.subheadline) }
                        if !card.notes.isEmpty { Text(card.notes).font(.subheadline).foregroundStyle(.secondary) }
                        Text(card.clipID.isEmpty ? "Camera photo · Manually entered details" : "From video at \(Int(card.sourceSeconds) / 60):\(String(format: "%02d", Int(card.sourceSeconds) % 60)) · Manually entered")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .foregroundStyle(Palette.ink)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: 22))
                    .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(Palette.border) }
                }
            }.padding(20)
        }
        .background(Palette.background)
        .navigationTitle("Room photos").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .fullScreenCover(item: $viewingPhoto) { card in
            FullScreenRoomPhoto(title: card.name, source: .saved(card.id))
        }
        .task { await reload() }
        .sheet(item: $edit, onDismiss: { Task { await reload() } }) { card in
            RoomPhotoEditor(existing: card)
        }
        .confirmationDialog("Delete this room photo and its details?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }), titleVisibility: .visible) {
            Button("Delete room card", role: .destructive) {
                if let card = pendingDelete {
                    Task {
                        do { try await RoomPhotoStore.shared.delete(card.id); await reload() }
                        catch { self.error = error.localizedDescription }
                    }
                }
                pendingDelete = nil
            }
        }
        .alert("Room photos", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }
}

struct RoomPhotoEditor: View {
    var captured: CapturedRoomPhoto? = nil
    var existing: RoomPhotoCard? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = "Bedroom"
    @State private var unit: RoomDimensionUnit = .metres
    @State private var length = ""
    @State private var width = ""
    @State private var height = ""
    @State private var notes = ""
    @State private var skipUnitConversion = false
    @State private var roomID: UUID?
    @State private var rooms: [RoomPhotoCard] = []
    @State private var saving = false
    @State private var viewingFullScreen = false
    @State private var error: String?
    init(captured: CapturedRoomPhoto? = nil, existing: RoomPhotoCard? = nil) {
        self.captured = captured; self.existing = existing
        let unit = existing?.unit ?? .metres
        _roomID = State(initialValue: existing?.roomID)
        _name = State(initialValue: existing?.name ?? "")
        _type = State(initialValue: existing?.roomType ?? "Bedroom")
        _unit = State(initialValue: unit)
        _notes = State(initialValue: existing?.notes ?? "")
        _length = State(initialValue: existing?.lengthMetres.map { RoomPhotoCard.number($0 / unit.factor) } ?? "")
        _width = State(initialValue: existing?.widthMetres.map { RoomPhotoCard.number($0 / unit.factor) } ?? "")
        _height = State(initialValue: existing?.heightMetres.map { RoomPhotoCard.number($0 / unit.factor) } ?? "")
    }
    private func parse(_ text: String) -> Double? {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: Locale.current.decimalSeparator ?? ".", with: ".")
        guard let value = Double(clean), value.isFinite, value > 0 else { return nil }
        return value
    }
    private var valid: Bool {
        let emptyPair = length.isEmpty && width.isEmpty
        return !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
            (emptyPair || (parse(length) != nil && parse(width) != nil)) && (height.isEmpty || parse(height) != nil)
    }
    private func dimension(_ label: String, text: Binding<String>) -> some View {
        HStack { Text(label); Spacer(); TextField("Optional", text: text).keyboardType(.decimalPad).multilineTextAlignment(.trailing); Text(unit.symbol).foregroundStyle(.secondary) }
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if let captured, let image = UIImage(data: captured.jpeg) {
                        RoomPhotoPreviewButton(title: "captured photo", open: { viewingFullScreen = true }) {
                            Image(uiImage: image).resizable().scaledToFit().frame(maxHeight: 240)
                        }
                    } else if let existing {
                        RoomPhotoPreviewButton(title: existing.name, open: { viewingFullScreen = true }) {
                            RoomPhotoImage(id: existing.id)
                        }
                    }
                }
                Section("Identify this room or area") {
                    if !rooms.isEmpty {
                        Menu("Use an existing room’s details") {
                            ForEach(rooms) { room in
                                Button("\(room.roomType) · \(room.name)") { useRoom(room) }
                            }
                        }
                    }
                    Picker("Type", selection: $type) {
                        ForEach(["Uncategorised", "Bedroom", "Living room", "Kitchen", "Bathroom", "Balcony", "Plot", "Building", "Other"], id: \.self) { Text($0) }
                    }
                    TextField("Name, e.g. Bedroom 1", text: $name)
                    if existing != nil {
                        Button("Separate this photo into a new room") { roomID = UUID() }
                    }
                }
                Section {
                    Picker("Units", selection: $unit) { ForEach(RoomDimensionUnit.allCases, id: \.self) { Text($0.label).tag($0) } }
                    dimension("Length", text: $length)
                    dimension("Width", text: $width)
                    dimension("Height", text: $height)
                    if let l = parse(length), let w = parse(width), (l * w).isFinite {
                        LabeledContent("Rectangular area", value: "\(RoomPhotoCard.number(l * w)) \(unit.symbol)²")
                    }
                } header: { Text("Manually entered dimensions") } footer: {
                    Text("Add length and width together, or leave them empty and edit later. Feet are decimal feet. Calculated area assumes a rectangle; it is not the total area of an irregular room or property.")
                }
                Section("Notes") { TextField("Measurement source or other details", text: $notes, axis: .vertical).lineLimit(2...5) }
                Section {
                    Button(saving ? "Saving…" : "Save room card") { save() }.disabled(saving || !valid)
                } footer: { Text("Photos assigned to the same room share its category, name, dimensions and notes. Use separate names, such as Bedroom 1 and Bedroom 2, for different rooms. Unassigned video photos share only within that video.") }
            }
            .navigationTitle(existing == nil ? "New room photo" : "Edit room details").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) } }
            .interactiveDismissDisabled(saving)
            .fullScreenCover(isPresented: $viewingFullScreen) {
                if let captured {
                    FullScreenRoomPhoto(title: "Captured photo", source: .captured(captured.jpeg))
                } else if let existing {
                    FullScreenRoomPhoto(title: existing.name, source: .saved(existing.id))
                }
            }
            .task {
                do {
                    let property = existing?.propertyID ?? captured?.propertyID
                    let clip = existing?.clipID ?? captured?.clipID ?? ""
                    let all = try await RoomPhotoStore.shared.all()
                    var seen = Set<UUID>()
                    rooms = all.filter {
                        $0.propertyID == property && (property != nil || $0.clipID == clip) &&
                        $0.roomType != "Uncategorised" && seen.insert($0.roomID ?? $0.id).inserted
                    }
                } catch { self.error = error.localizedDescription }
            }
            .onChange(of: unit) { old, new in
                if skipUnitConversion { skipUnitConversion = false; return }
                for binding in [$length, $width, $height] {
                    if let value = parse(binding.wrappedValue) { binding.wrappedValue = RoomPhotoCard.number(value * old.factor / new.factor) }
                }
            }
            .alert("Unable to save room card", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func useRoom(_ room: RoomPhotoCard) {
        roomID = room.roomID
        type = room.roomType; name = room.name; notes = room.notes
        if unit != room.unit { skipUnitConversion = true; unit = room.unit }
        length = room.lengthMetres.map { RoomPhotoCard.number($0 / room.unit.factor) } ?? ""
        width = room.widthMetres.map { RoomPhotoCard.number($0 / room.unit.factor) } ?? ""
        height = room.heightMetres.map { RoomPhotoCard.number($0 / room.unit.factor) } ?? ""
    }
    private func save() {
        guard valid else { return }
        let card = RoomPhotoCard(id: existing?.id ?? UUID(), roomID: roomID, clipID: existing?.clipID ?? captured?.clipID ?? "",
            propertyID: existing?.propertyID ?? captured?.propertyID, sourceSeconds: existing?.sourceSeconds ?? captured?.sourceSeconds ?? 0,
            created: existing?.created ?? Date(), updated: Date(), roomType: type, name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            lengthMetres: parse(length).map { $0 * unit.factor }, widthMetres: parse(width).map { $0 * unit.factor },
            heightMetres: parse(height).map { $0 * unit.factor }, unit: unit, notes: notes.trimmingCharacters(in: .whitespacesAndNewlines), sessionID: existing?.sessionID ?? captured?.sessionID)
        saving = true
        Task {
            do { try await RoomPhotoStore.shared.save(card, jpeg: captured?.jpeg); dismiss() }
            catch { self.error = error.localizedDescription; saving = false }
        }
    }
}
