import SwiftUI
import OSLog

@main
struct MyPropertyVisit: App {
    private static let startupLogger = Logger(subsystem: "com.infinity-propview.app", category: "Startup")
    private let startupTime = ContinuousClock.now
    @State private var initialProperties: [Property]?
    @State private var startupProgress = 0.0
    @State private var showingStartupArtwork = true
    @State private var artworkShownAt: ContinuousClock.Instant?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("propertylens.theme.v1") private var theme = "system"

    init() {
        Self.startupLogger.notice("SwiftUI app initialized")
    }

    private var colorScheme: ColorScheme? {
        switch theme { case "light": .light; case "dark": .dark; default: nil }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                if let initialProperties {
                    ContentView(properties: initialProperties)
                        .allowsHitTesting(!showingStartupArtwork)
                        .accessibilityHidden(showingStartupArtwork)
                        .onAppear(perform: homeAppeared)
                }

                if showingStartupArtwork {
                    StartupArtwork(progress: startupProgress)
                        .transition(.opacity)
                        .zIndex(1)
                        .onAppear {
                            if artworkShownAt == nil { artworkShownAt = .now }
                        }
                }
            }
            .preferredColorScheme(showingStartupArtwork ? nil : colorScheme)
            .task { await loadProperties() }
            .task(id: startupProgress == 1) {
                guard startupProgress == 1, showingStartupArtwork else { return }
                let clock = ContinuousClock()
                let shownAt = artworkShownAt ?? clock.now
                do { try await clock.sleep(until: shownAt.advanced(by: .seconds(2))) }
                catch { return }
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.24)) {
                    showingStartupArtwork = false
                }
                let elapsed = shownAt.duration(to: clock.now).components
                let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
                Self.startupLogger.notice("Startup artwork handed off to Home after \(milliseconds, privacy: .public) ms")
            }
        }
    }

    private func loadProperties() async {
        guard initialProperties == nil else { return }
        startupProgress = 1.0 / 3
        let properties = await Task.detached(priority: .userInitiated) {
            let saved = UserDefaults.standard.string(forKey: Property.storageKey) ?? "[]"
            return (try? JSONDecoder().decode([Property].self, from: Data(saved.utf8))) ?? []
        }.value
        guard !Task.isCancelled else { return }
        startupProgress = 2.0 / 3
        initialProperties = properties
        Self.startupLogger.notice("Saved properties loaded")
    }

    private func homeAppeared() {
        guard startupProgress < 1 else { return }
        startupProgress = 1
        let elapsed = startupTime.duration(to: .now).components
        let milliseconds = elapsed.seconds * 1_000 + elapsed.attoseconds / 1_000_000_000_000_000
        Self.startupLogger.notice("Home appeared \(milliseconds, privacy: .public) ms after SwiftUI app initialization")
    }
}

private struct StartupArtwork: View {
    let progress: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var appearance

    var body: some View {
        GeometryReader { geometry in
            let traits = UITraitCollection(userInterfaceStyle: appearance == .dark ? .dark : .light)
            ZStack {
                Color("LaunchBackground")
                if let artwork = UIImage(named: "LaunchBackdrop", in: .main, compatibleWith: traits) {
                    Image(uiImage: artwork)
                        .accessibilityHidden(true)
                } else {
                    VStack(spacing: 16) {
                        Image(decorative: "LaunchGlyph")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 72, height: 72)
                            .background(.indigo, in: RoundedRectangle(cornerRadius: 16))
                        Text("MyPropertyVisit").font(.title.bold())
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()

            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(appearance == .dark ? Color(red: 0.78, green: 0.72, blue: 0.98) : .indigo)
                .frame(width: 132)
                .position(x: geometry.size.width / 2, y: geometry.size.height * 0.68)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: progress)
                .accessibilityLabel("Loading MyPropertyVisit")
        }
        .ignoresSafeArea()
    }
}
