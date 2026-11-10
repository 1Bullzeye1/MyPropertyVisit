import SwiftUI
import Photos
import AVFoundation
import AVKit
import CoreLocation
import CoreImage
import UIKit

struct HeadingSample: Codable, Sendable {
    let seconds: Double
    let degrees: Double
    let accuracy: Double
}

struct Walkthrough: Codable, Identifiable, Sendable {
    var id: String
    var created: Date
    var propertyID: String?
    var headings: [HeadingSample]
    var sessionID: UUID? = nil
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

struct CaptureVisit: Codable, Identifiable, Sendable {
    var id: UUID
    var propertyID: String?
    var created: Date
    var ended: Date?
    var title: String { "Visit · " + created.formatted(date: .abbreviated, time: .standard) }
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("CaptureSessions", isDirectory: true)
    }
    func save(in directory: URL = Self.directory) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(id.uuidString + ".json"), options: .atomic)
    }
    static func load(propertyID: String?, in directory: URL = Self.directory) throws -> [Self] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try JSONDecoder().decode(Self.self, from: Data(contentsOf: $0)) }
            .filter { propertyID == nil || $0.propertyID == propertyID }.sorted { $0.created > $1.created }
    }
}

// Anchor each active span to the movie's recorded duration; paused wall time is excluded.
struct RecordingTimeline: Sendable {
    private var anchor: Date?
    private(set) var offset: Double = 0
    mutating func resume(at date: Date, recordedSeconds: Double) {
        offset = recordedSeconds.isFinite ? max(0, recordedSeconds) : 0
        anchor = date
    }
    mutating func pause(recordedSeconds: Double) {
        offset = recordedSeconds.isFinite ? max(offset, recordedSeconds) : offset
        anchor = nil
    }
    func seconds(at date: Date) -> Double? {
        guard let anchor, date >= anchor else { return nil }
        return offset + date.timeIntervalSince(anchor)
    }
}

// The capture session is shared only to attach AVFoundation's preview layer on
// the main actor. All session configuration and start/stop operations belong to
// CameraEngine. No mutable application state is stored in this bridge.
private final class CameraPreviewSource: @unchecked Sendable {
    let session = AVCaptureSession()
}

struct CameraZoomConfiguration: Sendable {
    var minimum: Double = 1
    var maximum: Double = 1
    var current: Double = 1
    var presets: [Double] = [1]
    static func clamp(_ value: Double, minimum: Double, maximum: Double) -> Double {
        min(maximum, max(minimum, value.isFinite ? value : 1))
    }
    static func choices(minimum: Double, maximum: Double, native: [Double]) -> [Double] {
        let values = ([minimum, 1, 2] + native).filter { $0 >= minimum && $0 <= maximum }.sorted()
        return values.reduce(into: []) { result, value in
            if result.last.map({ abs($0 - value) > 0.02 }) ?? true { result.append(value) }
        }
    }
}

private enum CameraEvent: Sendable {
    case started(Date)
    case paused(Double)
    case resumed(Date, Double)
    case finished(success: Bool, message: String?)
}

// Blocking AVFoundation capture operations run on this actor, never the UI actor.
private actor CameraEngine: NSObject, AVCaptureFileOutputRecordingDelegate, AVCapturePhotoCaptureDelegate {
    private let preview: CameraPreviewSource
    private let output = AVCaptureMovieFileOutput()
    private let photoOutput = AVCapturePhotoOutput()
    private var photoContinuation: CheckedContinuation<Data, Error>?
    private let event: @Sendable (CameraEvent) -> Void
    private var device: AVCaptureDevice?
    private var zoomMultiplier: Double = 1
    private var configured = false
    private var stopRequested = false

    init(preview: CameraPreviewSource, event: @escaping @Sendable (CameraEvent) -> Void) {
        self.preview = preview
        self.event = event
    }

    func prepare() throws {
        let session = preview.session
        if !configured {
            let types: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera]
            guard let camera = types.compactMap({ AVCaptureDevice.default($0, for: .video, position: .back) }).first else {
                throw NSError(domain: "MyPropertyVisit.Camera", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Camera unavailable. Recording requires a physical iPhone."])
            }
            let input = try AVCaptureDeviceInput(device: camera)
            session.beginConfiguration()
            defer { session.commitConfiguration() }
            session.sessionPreset = .high
            guard session.canAddInput(input) else {
                throw NSError(domain: "MyPropertyVisit.Camera", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to configure the camera input."])
            }
            session.addInput(input)
            guard session.canAddOutput(output) else {
                session.removeInput(input)
                throw NSError(domain: "MyPropertyVisit.Camera", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to configure video recording."])
            }
            session.addOutput(output)
            if session.canAddOutput(photoOutput) { session.addOutput(photoOutput) }
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            device = camera
            if #available(iOS 18.0, *) {
                zoomMultiplier = Double(camera.displayVideoZoomFactorMultiplier)
            } else if let wideIndex = camera.constituentDevices.firstIndex(where: { $0.deviceType == .builtInWideAngleCamera }), wideIndex > 0 {
                zoomMultiplier = 1 / camera.virtualDeviceSwitchOverVideoZoomFactors[wideIndex - 1].doubleValue
            }
            configured = true
        }
        if !session.isRunning { session.startRunning() }
    }

    func zoomConfiguration() -> CameraZoomConfiguration {
        guard let device else { return CameraZoomConfiguration() }
        let minimum = Double(device.minAvailableVideoZoomFactor) * zoomMultiplier
        let native = device.virtualDeviceSwitchOverVideoZoomFactors.map { $0.doubleValue * zoomMultiplier }
        let maximum = min(Double(device.maxAvailableVideoZoomFactor) * zoomMultiplier, max(10, native.max() ?? 1))
        return CameraZoomConfiguration(minimum: minimum, maximum: maximum,
            current: Double(device.videoZoomFactor) * zoomMultiplier,
            presets: CameraZoomConfiguration.choices(minimum: minimum, maximum: maximum, native: native))
    }

    func setZoom(_ displayValue: Double) throws -> Double {
        guard let device else { return 1 }
        let limits = zoomConfiguration()
        let display = CameraZoomConfiguration.clamp(displayValue, minimum: limits.minimum, maximum: limits.maximum)
        let raw = CGFloat(display / zoomMultiplier)
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.cancelVideoZoomRamp()
        device.videoZoomFactor = min(device.maxAvailableVideoZoomFactor, max(device.minAvailableVideoZoomFactor, raw))
        return Double(device.videoZoomFactor) * zoomMultiplier
    }

    private var paused: Bool {
        if #available(iOS 18.0, *) { return output.isRecordingPaused }
        return false
    }

    @available(iOS 18.0, *)
    func togglePause() {
        if output.isRecordingPaused { output.resumeRecording() }
        else if output.isRecording { output.pauseRecording() }
    }

    @available(iOS 18.0, *)
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didPauseRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let duration = output.recordedDuration.seconds
        Task { await reportPause(duration) }
    }

    private func reportPause(_ duration: Double) { event(.paused(duration)) }

    @available(iOS 18.0, *)
    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didResumeRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let date = Date()
        let duration = output.recordedDuration.seconds
        Task { await reportResume(date, duration) }
    }

    private func reportResume(_ date: Date, _ duration: Double) { event(.resumed(date, duration)) }

    func capturePhoto() async throws -> Data {
        guard photoContinuation == nil, (!output.isRecording || paused),
              photoOutput.connection(with: .video) != nil else { throw RoomPhotoError.missingPhoto }
        if let connection = photoOutput.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        return try await withCheckedThrowingContinuation { continuation in
            photoContinuation = continuation
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        Task { await finishPhoto(data) }
    }

    nonisolated func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil { Task { await finishPhoto(nil) } }
    }

    private func finishPhoto(_ data: Data?) {
        if let data { photoContinuation?.resume(returning: data) }
        else { photoContinuation?.resume(throwing: RoomPhotoError.missingPhoto) }
        photoContinuation = nil
    }

    func start(to url: URL) {
        stopRequested = false
        output.startRecording(to: url, recordingDelegate: self)
    }

    func stop() {
        stopRequested = true
        if output.isRecording || paused { output.stopRecording() }
    }

    func shutdown() {
        stop()
        if preview.session.isRunning { preview.session.stopRunning() }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        let date = Date()
        Task { await didStart(at: date) }
    }

    private func didStart(at date: Date) {
        event(.started(date))
        if stopRequested { output.stopRecording() }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        let nsError = error as NSError?
        let success = error == nil || nsError?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool == true
        let message = error?.localizedDescription
        // Only immutable values cross from the delegate callback to the actor.
        Task { await didFinish(success: success, message: message) }
    }

    private func didFinish(success: Bool, message: String?) {
        event(.finished(success: success, message: message))
    }
}

private struct CompassReading: Sendable {
    let magneticHeading: Double
    let headingAccuracy: Double
    let timestamp: Date
}

@MainActor
private final class LiveCompass: ObservableObject {
    @Published var bearing: Double?
}

private struct LiveCompassView: View {
    @ObservedObject var compass: LiveCompass
    var body: some View { CompassDial(bearing: compass.bearing) }
}

@MainActor
final class WalkthroughRecorder: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let preview = CameraPreviewSource()
    var session: AVCaptureSession { preview.session }
    private lazy var camera = CameraEngine(preview: preview) { [weak self] event in
        Task { @MainActor in self?.handle(event) }
    }
    private let location = CLLocationManager()
    private var timeline = RecordingTimeline()
    private var pending: Walkthrough?
    private var preparing = false
    private var wantsCamera = false
    private var stopRequested = false
    @Published var ready = false
    @Published var recording = false
    @Published var paused = false
    @Published var visit: CaptureVisit?
    @Published var busy = false
    private var heading: CompassReading?
    fileprivate let liveCompass = LiveCompass()

    private func updateHeading(_ reading: CompassReading?) {
        heading = reading
        liveCompass.bearing = reading?.magneticHeading
    }
    @Published var message = "Preparing camera…"
    @Published var error: String?
    @Published var refresh = UUID()
    @Published var photoSaved = false
    @Published var zoom = CameraZoomConfiguration()
    @Published var zoomValue: Double = 1
    private var zoomTask: Task<Void, Never>?
    private var zoomInitialised = false

    func changeZoom(_ value: Double) {
        guard ready, !busy else { return }
        let requested = CameraZoomConfiguration.clamp(value, minimum: zoom.minimum, maximum: zoom.maximum)
        zoomValue = requested
        zoomTask?.cancel()
        zoomTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(35))
                try Task.checkCancellation()
                let actual = try await camera.setZoom(requested)
                if zoomValue == requested { zoomValue = actual }
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }

    @discardableResult
    private func ensureVisit(propertyID: String?) throws -> CaptureVisit {
        if let visit { return visit }
        let value = CaptureVisit(id: UUID(), propertyID: propertyID, created: Date())
        try value.save()
        visit = value
        return value
    }

    func endVisit() {
        guard !recording, !busy, var value = visit else { return }
        value.ended = Date()
        do { try value.save(); visit = nil; refresh = UUID() }
        catch { self.error = error.localizedDescription }
    }

    @available(iOS 18.0, *)
    func togglePause() {
        guard recording, !busy else { return }
        busy = true
        Task { await camera.togglePause() }
    }

    func takePhoto(propertyID: String?) async {
        guard ready, (!recording || paused), !busy else { return }
        busy = true
        defer { busy = false; if !wantsCamera { endVisit() } }
        do {
            let captureVisit = try ensureVisit(propertyID: propertyID)
            let bearing = heading?.magneticHeading
            let data = try await camera.capturePhoto()
            let jpeg = try await Task.detached(priority: .userInitiated) {
                guard let image = UIImage(data: data) else { throw RoomPhotoError.missingPhoto }
                return try RoomPhotoCapture.compassJPEG(image, bearing: bearing)
            }.value
            let card = RoomPhotoCard(id: UUID(), clipID: "", propertyID: propertyID, sourceSeconds: 0,
                created: Date(), updated: Date(), roomType: "Uncategorised", name: "Photo " + UUID().uuidString.prefix(6),
                lengthMetres: nil, widthMetres: nil, heightMetres: nil, unit: .metres, notes: "", sessionID: captureVisit.id)
            try await RoomPhotoStore.shared.save(card, jpeg: jpeg)
            photoSaved = true
        } catch { self.error = error.localizedDescription }
    }


    override init() {
        super.init()
        location.delegate = self
        location.headingFilter = 2
        location.headingOrientation = .portrait
    }

    func prepare() {
        wantsCamera = true
        guard !preparing else { return }
        preparing = true
        if CLLocationManager.headingAvailable() {
            location.startUpdatingHeading()
            message = "Hold iPhone upright. Compass follows the top edge of your phone, relative to magnetic north."
        } else {
            message = "Compass unavailable. Use a physical iPhone to test camera and compass."
        }
        Task {
            defer { preparing = false }
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            guard wantsCamera else { return }
            guard allowed else {
                ready = false
                message = "Camera access is off. Enable it in Settings to record a walkthrough."
                return
            }
            do {
                try await camera.prepare()
                guard wantsCamera else { await camera.shutdown(); return }
                if !zoomInitialised {
                    _ = try await camera.setZoom(1)
                    zoomInitialised = true
                }
                zoom = await camera.zoomConfiguration()
                zoomValue = zoom.current
                guard wantsCamera else { await camera.shutdown(); return }
                ready = true
            } catch {
                ready = false
                message = error.localizedDescription
            }
        }
    }

    func start(propertyID: String?) {
        guard ready, !busy, !recording else { return }
        do {
            try FileManager.default.createDirectory(at: Walkthrough.directory, withIntermediateDirectories: true)
            let captureVisit = try ensureVisit(propertyID: propertyID)
            let item = Walkthrough(id: UUID().uuidString, created: Date(), propertyID: propertyID, headings: [], sessionID: captureVisit.id)
            pending = item
            stopRequested = false
            busy = true
            Task { await camera.start(to: item.movie) }
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        stopRequested = true
        guard recording || busy else { return }
        busy = true
        Task { await camera.stop() }
    }

    func shutdown() {
        endVisit()
        wantsCamera = false
        zoomTask?.cancel()
        stop()
        ready = false
        location.stopUpdatingHeading()
        Task { await camera.shutdown() }
    }

    private func handle(_ event: CameraEvent) {
        switch event {
        case .started(let date):
            timeline.resume(at: date, recordedSeconds: 0)
            paused = false
            recording = true
            busy = false
            if stopRequested || !wantsCamera || UIApplication.shared.applicationState != .active { stop() }
            appendCurrentHeading(at: 0)
        case .paused(let duration):
            guard recording else { return }
            timeline.pause(recordedSeconds: duration)
            pending?.headings.removeAll { $0.seconds > timeline.offset }
            paused = true; busy = stopRequested
        case .resumed(let date, let duration):
            guard recording else { return }
            timeline.resume(at: date, recordedSeconds: duration)
            paused = false; busy = false
            appendCurrentHeading(at: timeline.offset)
            if stopRequested || !wantsCamera || UIApplication.shared.applicationState != .active { stop() }
        case .finished(let success, let failure):
            defer {
                recording = false; paused = false; busy = false; timeline = RecordingTimeline(); pending = nil
                if !wantsCamera { endVisit() }
            }
            guard success, let item = pending else {
                error = failure ?? "Recording could not be saved."
                return
            }
            do {
                try JSONEncoder().encode(item).write(to: item.metadata, options: .atomic)
                refresh = UUID()
            } catch { self.error = "Video saved, but its compass details could not be saved: \(error.localizedDescription)" }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        let reading = CompassReading(magneticHeading: newHeading.magneticHeading,
            headingAccuracy: newHeading.headingAccuracy, timestamp: newHeading.timestamp)
        Task { @MainActor in
            guard reading.headingAccuracy >= 0 else { self.updateHeading(nil); return }
            self.updateHeading(reading)
            self.append(reading)
        }
    }

    private func append(_ value: CompassReading) {
        guard recording, !paused, let seconds = timeline.seconds(at: value.timestamp),
              seconds >= (pending?.headings.last?.seconds ?? 0) else { return }
        pending?.headings.append(HeadingSample(seconds: seconds,
            degrees: value.magneticHeading, accuracy: value.headingAccuracy))
    }

    private func appendCurrentHeading(at seconds: Double) {
        guard let heading else { return }
        pending?.headings.append(HeadingSample(seconds: seconds, degrees: heading.magneticHeading, accuracy: heading.headingAccuracy))
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in self.updateHeading(nil); self.message = "Compass unavailable: \(message)" }
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
        layer.videoGravity = .resizeAspectFill
        if let connection = layer.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
        return view
    }
    func updateUIView(_ uiView: Preview, context: Context) {}
}

struct WalkthroughView: View {
    var propertyID: String? = nil
    @StateObject private var recorder = WalkthroughRecorder()
    @Environment(\.scenePhase) private var phase
    @State private var showingInfo = false
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            CameraPreview(session: recorder.session)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()

            HStack(alignment: .top) {
                LiveCompassView(compass: recorder.liveCompass)
                Spacer()
                Label(recorder.paused ? "PAUSED" : (recorder.recording ? "REC" : "Video only"), systemImage: recorder.paused ? "pause.circle.fill" : (recorder.recording ? "record.circle.fill" : "speaker.slash"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(recorder.paused ? .yellow : (recorder.recording ? .red : .white))
                    .padding(10).background(.black.opacity(0.65), in: Capsule())
                    .accessibilityLabel(recorder.paused ? "Recording paused; you can take photos" : (recorder.recording ? "Recording video without audio" : "Video without audio"))
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
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                HStack {
                    Text(recorder.visit?.title ?? "A new visit starts with your first capture")
                        .font(.caption).lineLimit(1)
                    Spacer()
                    if recorder.visit != nil {
                        Button("End session") { recorder.endVisit() }
                            .font(.caption.bold()).disabled(recorder.recording || recorder.busy)
                    }
                }
                if recorder.ready && recorder.zoom.maximum > recorder.zoom.minimum {
                    HStack(spacing: 12) {
                        ForEach(recorder.zoom.presets, id: \.self) { value in
                            let selected = abs(recorder.zoomValue - value) < 0.05
                            Button { recorder.changeZoom(value) } label: {
                                Text(value.formatted(.number.precision(.fractionLength(0...1))) + "×")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .background(selected ? Color.yellow.opacity(0.35) : Color.white.opacity(0.12), in: Capsule())
                            }
                            .accessibilityLabel("Zoom \(value.formatted()) times")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }.disabled(recorder.busy)
                }
                HStack {
                    NavigationLink {
                        PropertyMediaLibrary(propertyID: propertyID)
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "photo.stack").font(.title2)
                            Text("Library").font(.caption)
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
                    if #available(iOS 18.0, *), recorder.recording {
                        Button { recorder.togglePause() } label: {
                            VStack(spacing: 5) {
                                Image(systemName: recorder.paused ? "play.fill" : "pause.fill").font(.title2)
                                Text(recorder.paused ? "Resume" : "Pause").font(.caption)
                            }.frame(maxWidth: .infinity)
                        }.disabled(recorder.busy)
                    }
                    Button { Task { await recorder.takePhoto(propertyID: propertyID) } } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "camera.fill").font(.title2)
                            Text("Photo").font(.caption)
                        }.frame(maxWidth: .infinity)
                    }.disabled(!recorder.ready || (recorder.recording && !recorder.paused) || recorder.busy)
                    Button { showingInfo = true } label: {
                        VStack(spacing: 5) {
                            Image(systemName: "info.circle").font(.title2)
                            Text("Info").font(.caption)
                        }.frame(maxWidth: .infinity)
                    }
                }
            }
            .foregroundStyle(.white)
            .padding(12)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 22))
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
        .alert("Photo saved", isPresented: $recorder.photoSaved) {
            Button("OK", role: .cancel) {}
        } message: { Text("Saved in this visit under Photos & videos → Sessions. Add room details whenever you are ready.") }
        .sheet(isPresented: $showingInfo) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Label("Video only · Saved offline", systemImage: "video").font(.headline)
                        Text("Only the rear camera is recorded. Audio and app controls are excluded.")
                        Label("Camera zoom", systemImage: "plus.magnifyingglass").font(.headline)
                        Text("Tap a zoom button. Available wide and telephoto views depend on this iPhone. iOS chooses the camera lens automatically; some zoom levels use digital cropping. Zoom affects saved photos and videos, including while recording.")
                        Label("Pause and photos", systemImage: "pause.circle").font(.headline)
                        Text("On iOS 18 or later, tap Pause, take one or more photos, then Resume. Stop saves one video with paused time left out. All captures belong to the current visit; End session starts a fresh visit for your next capture.")
                        Label("Reading the compass", systemImage: "safari").font(.headline)
                        Text("The red needle and N point toward magnetic north. The gold marker at the top shows your phone direction; degrees appear below. Hold your phone upright and away from magnets.")
                        Text(recorder.message).foregroundStyle(.secondary)
                        Label("Sharing", systemImage: "square.and.arrow.up").font(.headline)
                        Text("Use Share or save media in Photos & videos to share selected photos and compass videos, or save them to Photos. You can also export a single photo or video.")
                    }.padding(24)
                }
                .navigationTitle("Recording guide").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingInfo = false } } }
            }.presentationDetents([.medium, .large])
        }
        .navigationTitle("Record walkthrough").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(.white)
        .navigationBarBackButtonHidden(recorder.recording || recorder.busy)
        .task { recorder.prepare() }
        .onChange(of: phase) { if phase != .active { recorder.stop() } else { recorder.prepare() } }
        .onReceive(NotificationCenter.default.publisher(for: AVCaptureSession.wasInterruptedNotification, object: recorder.session)) { _ in recorder.stop() }
        .onDisappear { recorder.shutdown() }
        .alert("Recording", isPresented: Binding(get: { recorder.error != nil }, set: { if !$0 { recorder.error = nil } })) {
            Button("OK") { recorder.error = nil }
        } message: { Text(recorder.error ?? "") }
    }
}

struct WalkthroughPlayback: View {
    let clip: Walkthrough
    @State private var player: AVPlayer?
    @State private var exporting = false
    @State private var exportedURL: URL?
    @State private var sharePresented = false
    @State private var exportError: String?
    @State private var capturedRoom: CapturedRoomPhoto?
    @State private var capturingRoom = false
    @State private var roomCaptureTask: Task<Void, Never>?
    var body: some View {
        VStack(spacing: 20) {
            VideoPlayer(player: player)
            HStack {
                Button {
                    guard let player else { return }
                    player.pause()
                    let seconds = player.currentTime().seconds
                    capturingRoom = true
                    roomCaptureTask = Task { @MainActor in
                        defer { capturingRoom = false }
                        do { capturedRoom = try await RoomPhotoCapture.capture(clip, seconds: seconds) }
                        catch is CancellationError { }
                        catch { exportError = error.localizedDescription }
                    }
                } label: {
                    Label(capturingRoom ? "Capturing…" : "Capture room photo", systemImage: "camera.viewfinder")
                }.disabled(player == nil || capturingRoom || exporting)
                Spacer()
                NavigationLink { RoomPhotoLibrary(clipID: clip.id) } label: {
                    Label("Room photos", systemImage: "photo.on.rectangle")
                }
            }.font(.subheadline)
            TimelineView(.periodic(from: .now, by: 0.25)) { _ in
                let time = player?.currentTime().seconds ?? 0
                let sample = clip.headings.last { $0.seconds <= time }
                if let sample, time - sample.seconds < 5 {
                    CompassDial(bearing: sample.degrees)
                    Text("Red needle: magnetic north · Top marker: phone direction")
                        .font(.caption).foregroundStyle(.secondary)
                } else { Text("No compass reading at this point").foregroundStyle(.secondary) }
            }
            Button {
                exporting = true
                player?.pause()
                Task { @MainActor in
                    do {
                        exportedURL = try await CompassVideoExporter.export(clip)
                        sharePresented = true
                    } catch { exportError = error.localizedDescription }
                    exporting = false
                }
            } label: {
                Label(exporting ? "Preparing compass video…" : "Share video with compass", systemImage: "square.and.arrow.up")
            }.disabled(exporting || capturingRoom)
            NavigationLink("Save video to Photos") { MediaExportView(clips: [clip], photos: []) }
            if exporting { ProgressView() }
            Text("The shared video includes recorded magnetic bearings. Missing readings are labelled unavailable. Keep this screen open while preparing the video.")
                .font(.footnote).foregroundStyle(.secondary)
        }.padding().navigationTitle("Walkthrough").navigationBarTitleDisplayMode(.inline)
        .task {
            if player == nil { player = AVPlayer(url: clip.movie) }
        }
        .onDisappear { player?.pause(); roomCaptureTask?.cancel() }
        .sheet(item: $capturedRoom) { photo in RoomPhotoEditor(captured: photo) }
        .sheet(isPresented: $sharePresented, onDismiss: {
            if let exportedURL { try? FileManager.default.removeItem(at: exportedURL) }
            exportedURL = nil
        }) {
            if let exportedURL { WalkthroughShareSheet(url: exportedURL) }
        }
        .alert("Walkthrough", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
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

enum CompassVideoExporter {
    @MainActor static func export(_ clip: Walkthrough) async throws -> URL {
        let asset = AVURLAsset(url: clip.movie)
        // AVFoundation supplies oriented frames, preserving the source movie's rotation.
        let cache = CompassImageCache()
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
                    request.finish(with: NSError(domain: "MyPropertyVisit.Export", code: 2,
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
            throw NSError(domain: "MyPropertyVisit.Export", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Video export is not available for this recording."])
        }
        let type: AVFileType = exporter.supportedFileTypes.contains(.mp4) ? .mp4 : .mov
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MyPropertyVisit-\(UUID().uuidString).\(type == .mp4 ? "mp4" : "mov")")
        exporter.outputURL = url
        exporter.outputFileType = type
        exporter.videoComposition = composition
        exporter.shouldOptimizeForNetworkUse = true
        return try await VideoExportOperation(exporter: exporter).run(to: url)
    }
}

// One renderer keeps the live dial, playback dial and exported video consistent.
enum CompassDialArtwork {
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

// NSCache access is guarded explicitly; cached CIImages are immutable. The cache
// never exposes its mutable storage to concurrent video frame callbacks.
private final class CompassImageCache: @unchecked Sendable {
    private let lock = NSLock()
    private let storage = NSCache<NSString, CIImage>()
    init() { storage.countLimit = 32 }
    func object(forKey key: NSString) -> CIImage? {
        lock.lock(); defer { lock.unlock() }
        return storage.object(forKey: key)
    }
    func setObject(_ image: CIImage, forKey key: NSString) {
        lock.lock(); defer { lock.unlock() }
        storage.setObject(image, forKey: key)
    }
}

// The legacy iOS 17 callback captures this main-actor owner, rather than passing
// the non-Sendable AVAssetExportSession into a concurrent closure.
@MainActor
private final class VideoExportOperation {
    private let exporter: AVAssetExportSession
    init(exporter: AVAssetExportSession) { self.exporter = exporter }
    func run(to url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            exporter.exportAsynchronously { [self] in
                Task { @MainActor in
                    if exporter.status == .completed { continuation.resume(returning: url) }
                    else {
                        try? FileManager.default.removeItem(at: url)
                        continuation.resume(throwing: exporter.error ?? NSError(domain: "MyPropertyVisit.Export", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "Video export was interrupted. Please try again."]))
                    }
                }
            }
        }
    }
}

// Atomic sidecar writes update the parent directory. Reuse the decoded listing
// across library and session screens until media is saved or removed.
private actor MediaListing {
    static let shared = MediaListing()
    private var videoStamp: Date?
    private var visitStamp: Date?
    private var videos: [Walkthrough]?
    private var visits: [CaptureVisit]?

    func load(propertyID: String?, sessionID: UUID?) -> ([Walkthrough], Result<[CaptureVisit], Error>) {
        let videoDate = modified(Walkthrough.directory)
        if videos == nil || videoStamp != videoDate || videoDate == nil {
            videos = Walkthrough.load(propertyID: nil)
            videoStamp = videoDate
        }
        let filtered = (videos ?? []).filter {
            (propertyID == nil || $0.propertyID == propertyID) && (sessionID == nil || $0.sessionID == sessionID)
        }
        guard sessionID == nil else { return (filtered, .success([])) }
        let sessions = Result {
            let visitDate = modified(CaptureVisit.directory)
            if visits == nil || visitStamp != visitDate || visitDate == nil {
                visits = try CaptureVisit.load(propertyID: nil)
                visitStamp = visitDate
            }
            return (visits ?? []).filter { propertyID == nil || $0.propertyID == propertyID }
        }
        return (filtered, sessions)
    }

    private func modified(_ directory: URL) -> Date? {
        try? directory.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }
}

struct PropertyMediaLibrary: View {
    var propertyID: String? = nil
    var visit: CaptureVisit? = nil
    @State private var clips: [Walkthrough] = []
    @State private var visits: [CaptureVisit] = []
    @State private var loadingMedia = true
    @State private var error: String?
    var body: some View {
        LensMenuPage(title: visit?.title ?? "Photos & videos") {
            LensMenuHeader(
                title: visit == nil ? "Your media library" : "Visit library",
                subtitle: visit?.title ?? "Browse walkthroughs, room photos and measurements.",
                symbol: "photo.stack"
            )

            NavigationLink { RoomPhotoLibrary(sessionID: visit?.id, propertyID: propertyID) } label: {
                LensMenuRow("Room photos & dimensions", "Browse photos and edit room details", "photo.on.rectangle")
            }.buttonStyle(.plain)

            if visit == nil {
                NavigationLink { WalkthroughView(propertyID: propertyID) } label: {
                    LensMenuRow("Take photos or record video", "Capture a walkthrough with compass readings", "video.circle")
                }.buttonStyle(.plain)

                Text("Sessions").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
                if !loadingMedia && visits.isEmpty {
                    LensMenuRow("No sessions yet", "New captures will be grouped by visit.", "folder", showsArrow: false)
                }
                ForEach(visits) { session in
                    NavigationLink { PropertyMediaLibrary(propertyID: session.propertyID, visit: session) } label: {
                        LensMenuRow(session.title, "Photos and videos from this visit", "folder")
                    }.buttonStyle(.plain)
                }
            }

            NavigationLink { MediaExportLoader(propertyID: propertyID, sessionID: visit?.id) } label: {
                LensMenuRow("Share or save media", "Select photos and videos, or save all to Photos", "square.and.arrow.up")
            }.buttonStyle(.plain)

            Text(visit == nil ? "All saved videos" : "Session videos")
                .font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            if loadingMedia {
                ProgressView("Loading videos").frame(maxWidth: .infinity).padding(.vertical, 20)
            } else if clips.isEmpty {
                LensMenuRow("No videos saved yet", "Recorded walkthroughs will appear here.", "play.rectangle", showsArrow: false)
            }
            ForEach(clips) { clip in
                NavigationLink { WalkthroughPlayback(clip: clip) } label: {
                    LensMenuRow(clip.created.formatted(date: .abbreviated, time: .shortened), "Play walkthrough", "play.rectangle")
                }.buttonStyle(.plain)
            }
        }
        .task {
            defer { loadingMedia = false }
            let (videos, sessions) = await MediaListing.shared.load(propertyID: propertyID, sessionID: visit?.id)
            guard !Task.isCancelled else { return }
            clips = videos
            do { visits = try sessions.get() }
            catch { self.error = error.localizedDescription }
        }
        .alert("Media library", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(error ?? "") }
    }
}


struct MediaExportLoader: View {
    var propertyID: String? = nil
    var sessionID: UUID? = nil
    @State private var clips: [Walkthrough] = []
    @State private var photos: [RoomPhotoCard] = []
    @State private var loaded = false
    @State private var error: String?
    var body: some View {
        Group {
            if loaded { MediaExportView(clips: clips, photos: photos) }
            else if let error { Text(error).padding() }
            else { ProgressView("Loading media") }
        }.task {
            do {
                let (videos, _) = await MediaListing.shared.load(propertyID: propertyID, sessionID: sessionID)
                photos = try await RoomPhotoStore.shared.all(propertyID: propertyID, sessionID: sessionID)
                clips = videos
                loaded = true
            } catch { self.error = error.localizedDescription }
        }
    }
}

struct MediaExportView: View {
    let clips: [Walkthrough]
    let photos: [RoomPhotoCard]
    @State private var selected: Set<String> = []
    @State private var initialized = false
    @State private var busy = false
    @State private var progress = ""
    @State private var message: String?
    @State private var urls: [URL] = []
    @State private var temporary: [URL] = []
    @State private var sharing = false
    @State private var shareReport: String?
    private var keys: [String] { photos.map { $0.id.uuidString } + clips.map { $0.id } }
    var body: some View {
        List {
            Section {
                Button(selected.count == keys.count ? "Deselect all" : "Select all") {
                    selected = selected.count == keys.count ? [] : Set(keys)
                }
                ForEach(photos) { photo in
                    selection(photo.id.uuidString, title: photo.name, symbol: "photo")
                }
                ForEach(clips) { clip in
                    selection(clip.id, title: "Video · " + clip.created.formatted(date: .abbreviated, time: .shortened), symbol: "video")
                }
            } header: { Text("Choose media (\(selected.count) selected)") }
            Section {
                Button("Save selected to Photos", systemImage: "square.and.arrow.down") { run(save: true) }
                    .disabled(selected.isEmpty)
                Button("Share selected", systemImage: "square.and.arrow.up") { run(save: false) }
                    .disabled(selected.isEmpty)
                Text("The compass stays embedded. Room dimensions and notes remain editable in MyPropertyVisit.").font(.footnote)
                if busy { ProgressView(); Text(progress).font(.footnote) }
            }
        }
        .navigationTitle("Share & save")
        .disabled(busy)
        .navigationBarBackButtonHidden(busy)
        .onAppear { if !initialized { selected = Set(keys); initialized = true } }
        .sheet(isPresented: $sharing, onDismiss: {
            cleanup(); message = shareReport; shareReport = nil
        }) { MediaShareSheet(urls: urls) }
        .alert("Export", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: { Text(message ?? "") }
    }
    private func selection(_ id: String, title: String, symbol: String) -> some View {
        Button {
            if selected.contains(id) { selected.remove(id) } else { selected.insert(id) }
        } label: {
            HStack {
                Image(systemName: symbol)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: selected.contains(id) ? "checkmark.circle.fill" : "circle")
            }
        }
    }
    private func cleanup() {
        for url in temporary { try? FileManager.default.removeItem(at: url) }
        temporary = []; urls = []
    }
    private func run(save: Bool) {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            if save {
                let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
                guard status == .authorized || status == .limited else {
                    message = "Allow MyPropertyVisit to add photos in iPhone Settings, then try again."
                    return
                }
            }
            cleanup()
            var failures = 0
            var completed = 0
            let total = selected.count
            let items: [(String, RoomPhotoCard?, Walkthrough?)] = photos.filter { selected.contains($0.id.uuidString) }.map { ($0.id.uuidString, $0, nil) }
                + clips.filter { selected.contains($0.id) }.map { ($0.id, nil, $0) }
            for (id, photo, clip) in items {
                progress = "Preparing \(completed + failures + 1) of \(total)…"
                do {
                    let url: URL
                    let video: Bool
                    if let photo {
                        url = try await RoomPhotoStore.shared.exportCopy(photo.id)
                        video = false
                    } else if let clip {
                        url = try await CompassVideoExporter.export(clip)
                        video = true
                    } else { continue }
                    temporary.append(url)
                    if save {
                        try await PHPhotoLibrary.shared().performChanges {
                            if video { PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url) }
                            else { PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: url) }
                        }
                        try? FileManager.default.removeItem(at: url)
                        selected.remove(id)
                    } else { urls.append(url) }
                    completed += 1
                } catch { failures += 1 }
            }
            if save {
                cleanup()
                message = "Saved \(completed) of \(total) items to Photos." + (failures > 0 ? " \(failures) failed. You can retry those items." : "")
            } else if !urls.isEmpty {
                sharing = true
                if failures > 0 { shareReport = "Prepared \(completed) items. \(failures) items could not be exported." }
            } else { cleanup(); message = "Could not export the selected media. Please try again." }
        }
    }
}

struct MediaShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
