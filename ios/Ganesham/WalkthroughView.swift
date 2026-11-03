import SwiftUI
import AVFoundation
import AVKit
import CoreLocation
import CoreImage
import UIKit

struct HeadingSample: Codable {
    let seconds: Double
    let degrees: Double
    let accuracy: Double
}

struct Walkthrough: Codable, Identifiable {
    var id: String
    var created: Date
    var propertyID: String?
    var headings: [HeadingSample]
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Walkthroughs", isDirectory: true)
    }
    var movie: URL { Self.directory.appendingPathComponent(id + ".mov") }
    var metadata: URL { Self.directory.appendingPathComponent(id + ".json") }
    static func load(propertyID: String?) -> [Self] {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }.compactMap {
            guard let data = try? Data(contentsOf: $0), let item = try? JSONDecoder().decode(Self.self, from: data),
                  FileManager.default.fileExists(atPath: item.movie.path),
                  propertyID == nil || item.propertyID == propertyID else { return nil }
            return item
        }.sorted { $0.created > $1.created }
    }
}

final class WalkthroughRecorder: NSObject, ObservableObject, CLLocationManagerDelegate, AVCaptureFileOutputRecordingDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "propertylens.camera")
    private let output = AVCaptureMovieFileOutput()
    private let location = CLLocationManager()
    private var started: Date?
    private var pending: Walkthrough?
    @Published var ready = false
    @Published var recording = false
    @Published var busy = false
    @Published var heading: CLHeading?
    @Published var message = "Preparing camera…"
    @Published var error: String?
    @Published var refresh = UUID()

    override init() {
        super.init()
        location.delegate = self
        location.headingFilter = 2
        location.headingOrientation = .portrait
    }
    func prepare() {
        if ready {
            if CLLocationManager.headingAvailable() { location.startUpdatingHeading() }
            queue.async { if !self.session.isRunning { self.session.startRunning() } }
            return
        }
        guard CLLocationManager.headingAvailable() else {
            message = "Compass unavailable. Use a physical iPhone to test camera and compass."
            configureCamera()
            return
        }
        location.startUpdatingHeading()
        message = "Hold iPhone upright. Compass follows the top edge of your phone, relative to magnetic north."
        configureCamera()
    }
    private func configureCamera() {
        Task { @MainActor in
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard allowed else {
                self.message = "Camera access is off. Enable it in Settings to record a walkthrough."
                return
            }
            queue.async {
                do {
                    guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                        DispatchQueue.main.async { self.message = "Camera unavailable. Recording requires a physical iPhone." }
                        return
                    }
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .high
                    let input = try AVCaptureDeviceInput(device: camera)
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration()
                        throw NSError(domain: "Camera", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to configure the camera."])
                    }
                    self.session.addInput(input)
                    self.session.addOutput(self.output)
                    if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                        connection.videoRotationAngle = 90
                    }
                    self.session.commitConfiguration()
                    self.session.startRunning()
                    DispatchQueue.main.async { self.ready = true }
                } catch { DispatchQueue.main.async { self.error = error.localizedDescription } }
            }
        }
    }
    func start(propertyID: String?) {
        guard ready, !busy, !recording else { return }
        do {
            try FileManager.default.createDirectory(at: Walkthrough.directory, withIntermediateDirectories: true)
            let item = Walkthrough(id: UUID().uuidString, created: Date(), propertyID: propertyID, headings: [])
            pending = item
            busy = true
            queue.async { self.output.startRecording(to: item.movie, recordingDelegate: self) }
        } catch { self.error = error.localizedDescription }
    }
    func stop() {
        guard recording, !busy else { return }
        busy = true
        queue.async { if self.output.isRecording { self.output.stopRecording() } }
    }
    func shutdown() {
        stop()
        location.stopUpdatingHeading()
        queue.async { if self.session.isRunning { self.session.stopRunning() } }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.started = Date()
            self.recording = true
            self.busy = false
            if UIApplication.shared.applicationState != .active { self.stop() }
            if let heading = self.heading { self.append(heading) }
        }
    }
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        DispatchQueue.main.async {
            defer { self.recording = false; self.busy = false; self.started = nil; self.pending = nil }
            let nsError = error as NSError?
            let success = error == nil || nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
            guard success, let item = self.pending else {
                self.error = error?.localizedDescription ?? "Recording could not be saved."
                return
            }
            do {
                try JSONEncoder().encode(item).write(to: item.metadata, options: .atomic)
                self.refresh = UUID()
            } catch { self.error = "Video saved, but its compass details could not be saved: \(error.localizedDescription)" }
        }
    }
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { heading = nil; return }
        heading = newHeading
        append(newHeading)
    }
    private func append(_ value: CLHeading) {
        guard let started, recording else { return }
        pending?.headings.append(HeadingSample(seconds: max(0, value.timestamp.timeIntervalSince(started)), degrees: value.magneticHeading, accuracy: value.headingAccuracy))
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        heading = nil
        message = "Compass unavailable: \(error.localizedDescription)"
    }
}

private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    }
    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        let layer = view.layer as! AVCaptureVideoPreviewLayer
        layer.session = session
        layer.videoGravity = .resizeAspect
        if let connection = layer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {}
}

struct WalkthroughView: View {
    var propertyID: String? = nil
    @StateObject private var recorder = WalkthroughRecorder()
    @Environment(\.scenePhase) private var phase
    @State private var clips: [Walkthrough] = []
    @State private var showingInfo = false
    private func reload() { clips = Walkthrough.load(propertyID: propertyID) }
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            CameraPreview(session: recorder.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(alignment: .top) {
                CompassDial(bearing: recorder.heading?.magneticHeading)
                Spacer()
                Label(recorder.recording ? "REC" : "Video only", systemImage: recorder.recording ? "record.circle.fill" : "speaker.slash")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recorder.recording ? .red : .white)
                    .padding(10).background(.black.opacity(0.65), in: Capsule())
                    .accessibilityLabel(recorder.recording ? "Recording video without audio" : "Video without audio")
            }.padding(16)
            if !recorder.ready {
                VStack(spacing: 14) {
                    Image(systemName: "video.slash").font(.largeTitle)
                    Text(recorder.message).multilineTextAlignment(.center)
                    if AVCaptureDevice.authorizationStatus(for: .video) == .denied {
                        Link("Open Settings", destination: URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
                .foregroundStyle(.white).padding(28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack {
                NavigationLink {
                    List {
                        if clips.isEmpty {
                            ContentUnavailableView("No walkthroughs yet", systemImage: "video", description: Text("Your saved recordings will be available here offline."))
                        }
                        ForEach(clips) { clip in
                            NavigationLink { WalkthroughPlayback(clip: clip) } label: {
                                Label(clip.created.formatted(date: .abbreviated, time: .shortened), systemImage: "play.rectangle")
                            }
                        }
                    }.navigationTitle("Walkthroughs")
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.stack").font(.title2)
                        Text("Saved (\(clips.count))").font(.caption)
                    }.frame(maxWidth: .infinity)
                }.disabled(recorder.recording || recorder.busy)
                Button {
                    if recorder.recording { recorder.stop() } else { recorder.start(propertyID: propertyID) }
                } label: {
                    ZStack {
                        Circle().strokeBorder(.white, lineWidth: 3).frame(width: 72, height: 72)
                        if recorder.busy {
                            ProgressView().tint(.white)
                        } else {
                            RoundedRectangle(cornerRadius: recorder.recording ? 7 : 32)
                                .fill(.red)
                                .frame(width: recorder.recording ? 30 : 58, height: recorder.recording ? 30 : 58)
                        }
                    }.frame(maxWidth: .infinity)
                }
                .accessibilityLabel(recorder.recording ? "Stop and save walkthrough" : "Start recording walkthrough")
                .disabled(!recorder.ready || recorder.busy)
                Button { showingInfo = true } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "info.circle").font(.title2)
                        Text("Info").font(.caption)
                    }.frame(maxWidth: .infinity)
                }
            }
            .foregroundStyle(.white).padding(.horizontal, 18).padding(.vertical, 14)
            .background(Color(white: 0.07))
        }
        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Video only · Saved offline", systemImage: "video").font(.headline)
                        Text("Only the rear camera is recorded. Audio and app controls are excluded.")
                        Label("Reading the compass", systemImage: "safari").font(.headline)
                        Text("The red needle and N point toward magnetic north. The gold marker at the top shows your phone direction; degrees appear below. Hold your phone upright and away from magnets.")
                        Text(recorder.message).foregroundStyle(.secondary)
                        Label("Sharing", systemImage: "square.and.arrow.up").font(.headline)
                        Text("Open a saved walkthrough and choose Share video with compass to embed the compass in the shared video.")
                    }.padding(24)
                }
                .navigationTitle("Recording guide").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInfo = false } } }
            }.presentationDetents([.medium, .large])
        }
        .navigationTitle("Record walkthrough").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(recorder.recording || recorder.busy)
        .task { recorder.prepare(); reload() }
        .onChange(of: recorder.refresh) { reload() }
        .onChange(of: phase) { if phase != .active { recorder.stop() } else { recorder.prepare() } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: recorder.session)) { _ in recorder.stop() }
        .onDisappear { recorder.shutdown() }
        .alert("Recording", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
            Button("OK") { recorder.error = nil }
        } message: { Text(recorder.error ?? "") }
    }
}

private struct WalkthroughPlayback: View {
    let clip: Walkthrough
    @State private var player: AVPlayer
    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var sharePresented = false
    @State private var exportError: String?
    init(clip: Walkthrough) { self.clip = clip; _player = State(initialValue: AVPlayer(url: clip.movie)) }
    var body: some View {
        VStack(spacing: 20) {
            VideoPlayer(player: player)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let time = player.currentTime().seconds
                let sample = clip.headings.last { $0.seconds <= time }
                if let sample, time - sample.seconds < 5 {
                    CompassDial(bearing: sample.degrees)
                    Text("Red needle: magnetic north · Top marker: phone direction")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("No compass reading at this point").foregroundStyle(.secondary) }
            }
            Button {
                exporting = true
                player.pause()
                Task { @MainActor in
                    do {
                        exportedURL = try await CompassVideoExporter.export(clip)
                        sharePresented = true
                    } catch { exportError = error.localizedDescription }
                    exporting = false
                }
            } label: {
                Label(exporting ? "Preparing compass video…" : "Share video with compass", systemImage: "square.and.arrow.up")
            }.disabled(exporting)
            if exporting { ProgressView() }
            Text("The shared video includes recorded magnetic bearings. Missing readings are labelled unavailable. Keep this screen open while preparing the video.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding().navigationTitle("Walkthrough").navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.pause() }
        .sheet(isPresented: $sharePresented, onDismiss: {
            if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
            exportedURL = nil
        }) {
            if let exportedURL { WalkthroughShareSheet(url: exportedURL) }
        }
        .alert("Unable to prepare video", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK") { exportError = nil }
        } message: { Text(exportError ?? "") }
    }
}

private struct WalkthroughShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private enum CompassVideoExporter {
    static func export(_ clip: Walkthrough) async throws -> URL {
        let asset = AVURLAsset(url: clip.movie)
        // AVFoundation supplies oriented frames, preserving the source movie's rotation.
        let cache = NSCache<NSString, CIImage>()
        cache.countLimit = 32
        let headings = clip.headings.sorted { $0.seconds < $1.seconds }
        let composition = AVVideoComposition(asset: asset) { request in
            let seconds = request.compositionTime.seconds
            let sample = headings.last { $0.seconds <= seconds }
            let bearing = sample.flatMap { seconds - $0.seconds < 5 && $0.accuracy >= 0 ? $0.degrees : nil }
            let key = (bearing.map { String(Int($0)) } ?? "unavailable") as NSString
            let badge: CIImage
            if let cached = cache.object(forKey: key) { badge = cached }
            else {
                let image = CompassDialArtwork.image(bearing: bearing.map { Double(Int($0)) })
                guard let rendered = CIImage(image: image) else {
                    request.finish(with: NSError(domain: "PropertyLens.Export", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Could not render the compass overlay."]))
                    return
                }
                badge = rendered
                cache.setObject(rendered, forKey: key)
            }
            let frame = request.sourceImage
            let scale = min(frame.extent.width, frame.extent.height) * 0.18 / 160
            let inset = frame.extent.width * 0.04
            let overlay = badge.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: frame.extent.minX + inset,
                    y: frame.extent.maxY - 196 * scale - inset))
            request.finish(with: overlay.composited(over: frame).cropped(to: frame.extent), context: nil)
        }
        guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw NSError(domain: "PropertyLens.Export", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Video export is not available for this recording."])
        }
        let type: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PropertyLens-\(UUID().uuidString).\(type == .mp4 ? "mp4" : "mov")")
        exporter.outputURL = url
        exporter.outputFileType = type
        exporter.videoComposition = composition
        exporter.shouldOptimizeForNetworkUse = true
        return try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously {
                if exporter.status == .completed { continuation.resume(returning: url) }
                else {
                    try? FileManager.default.removeItem(at: url)
                    continuation.resume(throwing: exporter.error ?? NSError(domain: "PropertyLens.Export", code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Video export was interrupted. Please try again."]))
                }
            }
        }
    }
}

// One renderer keeps the live dial, playback dial and exported video consistent.
private enum CompassDialArtwork {
    static func image(bearing: Double?) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 160, height: 196), format: format).image { renderer in
            let context = renderer.cgContext
            // Draw the readout outside the rotating compass coordinate system.
            UIColor(white: 0.04, alpha: 0.85).setFill()
            UIBezierPath(roundedRect: CGRect(x: 24, y: 162, width: 112, height: 32), cornerRadius: 12).fill()
            let readout = (bearing.map { "\(Int($0.rounded()) % 360)°" } ?? "—") as NSString
            let readoutStyle: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedDigitSystemFont(ofSize: 25, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let readoutSize = readout.size(withAttributes: readoutStyle)
            readout.draw(at: CGPoint(x: 80 - readoutSize.width / 2, y: 178 - readoutSize.height / 2), withAttributes: readoutStyle)
            context.translateBy(x: 80, y: 80)
            context.setFillColor(UIColor(white: 0.04, alpha: 0.85).cgColor)
            context.fillEllipse(in: CGRect(x: -77, y: -77, width: 154, height: 154))
            context.setStrokeColor(UIColor(white: 1, alpha: 0.35).cgColor)
            context.setLineWidth(1.5)
            context.strokeEllipse(in: CGRect(x: -75, y: -75, width: 150, height: 150))
            context.saveGState()
            context.rotate(by: -CGFloat(bearing ?? 0) * .pi / 180)
            for tick in 0..<24 {
                context.saveGState()
                context.rotate(by: CGFloat(tick) * .pi / 12)
                context.setStrokeColor(UIColor(white: 1, alpha: tick % 6 == 0 ? 0.95 : 0.4).cgColor)
                context.setLineWidth(tick % 6 == 0 ? 3 : 1.5)
                context.move(to: CGPoint(x: 0, y: -65))
                context.addLine(to: CGPoint(x: 0, y: tick % 6 == 0 ? -54 : -59))
                context.strokePath()
                context.restoreGState()
            }
            context.restoreGState()
            // Rotate the cardinal positions with magnetic north, keeping text upright.
            if let bearing {
                for (index, label) in ["N", "E", "S", "W"].enumerated() {
                    let angle = CGFloat(index) * .pi / 2 - .pi / 2 - CGFloat(bearing) * .pi / 180
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: UIFont.systemFont(ofSize: 19, weight: .bold),
                        .foregroundColor: index == 0 ? UIColor(red: 1, green: 0.40, blue: 0.43, alpha: 1) : UIColor.white
                    ]
                    let text = label as NSString
                    let size = text.size(withAttributes: attributes)
                    text.draw(at: CGPoint(x: cos(angle) * 48 - size.width / 2,
                                          y: sin(angle) * 48 - size.height / 2), withAttributes: attributes)
                }
            }
            // The stationary gold dot marks the top edge of the phone.
            context.setFillColor(UIColor(red: 1, green: 0.78, blue: 0.40, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: -4, y: -73, width: 8, height: 8))
            guard let bearing else {
                context.setStrokeColor(UIColor.lightGray.cgColor)
                context.setLineWidth(4)
                context.move(to: CGPoint(x: -23, y: 23))
                context.addLine(to: CGPoint(x: 23, y: -23))
                context.strokePath()
                return
            }
            context.rotate(by: -CGFloat(bearing) * .pi / 180)
            func needle(tip: CGFloat, color: UIColor) {
                context.setFillColor(color.cgColor)
                context.move(to: CGPoint(x: 0, y: tip))
                context.addLine(to: CGPoint(x: -10, y: 0))
                context.addLine(to: CGPoint(x: 10, y: 0))
                context.closePath()
                context.fillPath()
            }
            needle(tip: -33, color: UIColor(red: 1, green: 0.30, blue: 0.34, alpha: 1))
            needle(tip: 33, color: .white)
            context.setFillColor(UIColor(white: 0.12, alpha: 1).cgColor)
            context.fillEllipse(in: CGRect(x: -5, y: -5, width: 10, height: 10))
        }
    }
}

private struct CompassDial: View {
    let bearing: Double?
    var body: some View {
        Image(uiImage: CompassDialArtwork.image(bearing: bearing))
            .resizable().frame(width: 80, height: 98)
            .accessibilityLabel(bearing.map { "Magnetic bearing \(Int($0)) degrees" } ?? "Compass unavailable")
    }
}
