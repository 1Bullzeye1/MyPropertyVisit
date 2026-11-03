import SwiftUI

@main
struct PropertyLens: App {
    @AppStorage("propertylens.theme.v1") private var theme = "system"
    private var colorScheme: ColorScheme? {
        switch theme { case "light": .light; case "dark": .dark; default: nil }
    }
    var body: some Scene {
        WindowGroup {
            ContentView().preferredColorScheme(colorScheme)
        }
    }
}
