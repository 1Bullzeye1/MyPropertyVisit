// Compile after WalkthroughView.swift in one main.swift file so the checks use
// the actual private renderer/cache implementations, without exposing them in the app.
private let imageCache = CompassImageCache()
let images = (0..<8).map { index in
    CIImage(image: CompassDialArtwork.image(bearing: Double(index * 45)))!
}
DispatchQueue.concurrentPerform(iterations: 2000) { index in
    let slot = index % images.count
    let key = String(slot) as NSString
    imageCache.setObject(images[slot], forKey: key)
    if let retrieved = imageCache.object(forKey: key) {
        precondition(retrieved === images[slot], "Concurrent cache returned another bearing's image")
    }
}
for bearing: Double? in [0, 90, 180, 270, nil] {
    let dial = CompassDialArtwork.image(bearing: bearing)
    precondition(dial.size == CGSize(width: 160, height: 196), "Compass export dimensions changed")
    precondition(dial.cgImage != nil, "Compass failed to render")
}
let metadata = Walkthrough(id: "test", created: Date(timeIntervalSince1970: 0), propertyID: "property", headings: [
    HeadingSample(seconds: 0, degrees: 0, accuracy: 5),
    HeadingSample(seconds: 2, degrees: 90, accuracy: 8)
])
let roundTrip = try JSONDecoder().decode(Walkthrough.self, from: JSONEncoder().encode(metadata))
precondition(roundTrip.propertyID == "property" && roundTrip.headings.count == 2)
precondition(roundTrip.headings[1].seconds == 2 && roundTrip.headings[1].degrees == 90)
print("PASS: 2,000 concurrent cache operations; cardinal/unavailable rendering; compass metadata round-trip")
