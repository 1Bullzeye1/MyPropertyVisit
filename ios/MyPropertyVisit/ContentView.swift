import SwiftUI
import UIKit

struct Property: Identifiable, Codable, Hashable, Sendable {
    // Legacy storage keys preserve existing records across the display-name change.
    static let storageKey = "propertylens.properties.v1"

    var id = UUID()
    var name: String
    var type: String
    var location: String
}

enum Palette {
    // Light: indigo and lavender. Dark: aubergine and lavender.
    static let accent = adaptive(0x6250C8, dark: 0xC6B7FA)
    static let primaryAction = adaptive(0x6250C8, dark: 0x5945A4)
    static let ink = adaptive(0x25213D, dark: 0xF1ECFF)
    static let background = adaptive(0xF6F5FB, dark: 0x120F20)
    static let surface = adaptive(0xFFFFFF, dark: 0x201A32)
    static let border = adaptive(0xE8E4F3, dark: 0x423453)
    static let iconBackground = adaptive(0xEEEAFB, dark: 0x332747)
    static let coral = adaptive(0xBF4257, dark: 0xE6BC92)
    static let heroStart = adaptive(0x282148, dark: 0x282044)
    static let heroEnd = adaptive(0x514184, dark: 0x493675)
    static let heroEyebrow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(rgb: 0xDBD0FB)
            : UIColor(red: 0.86, green: 0.81, blue: 1, alpha: 1)
    })

    private static func adaptive(_ light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

struct ContentView: View {
    private enum MediaRoute: Hashable { case recorder, library }
    @State private var properties: [Property]
    @State private var create = false

    init(properties: [Property]) {
        _properties = State(initialValue: properties)
    }

    private func store(_ values: [Property]) {
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) {
            UserDefaults.standard.set(json, forKey: Property.storageKey)
            properties = values
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    HStack {
                        HStack(spacing: 10) {
                            Image(decorative: "BrandMark")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 36, height: 36)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text("MyPropertyVisit")
                                .font(.title2.bold())
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                                .foregroundStyle(Palette.ink)
                        }
                        Spacer()
                        NavigationLink { LensSettingsView() } label: {
                            Image(systemName: "gearshape").font(.title3)
                                .frame(width: 44, height: 44)
                                .background(Palette.surface, in: Circle())
                        }.buttonStyle(.plain).accessibilityLabel("Settings")
                    }
                    VStack(alignment: .leading, spacing: 18) {
                        Text("A CLEARER VIEW").font(.caption.weight(.semibold)).tracking(3)
                            .foregroundStyle(Palette.heroEyebrow)
                        Text("Every angle.\nEvery detail.")
                            .font(.system(.largeTitle, design: .serif).weight(.medium))
                        Text("Explore land, flats and buildings with the details that matter.")
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 18) {
                            Label("Walkthroughs", systemImage: "video")
                            Label("Directions", systemImage: "safari")
                        }.font(.caption)
                        Label("Manual dimensions", systemImage: "ruler").font(.caption)
                    }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [Palette.heroStart, Palette.heroEnd],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26)
                    )
                    VStack(spacing: 12) {
                        NavigationLink(value: MediaRoute.recorder) {
                            row("Record walkthrough", "Capture video with compass and take photos", "video.circle", primary: true)
                        }.buttonStyle(.plain)
                        NavigationLink(value: MediaRoute.library) {
                            row("Photos & videos", "Browse visits, videos and room measurements", "photo.on.rectangle")
                        }.buttonStyle(.plain)
                    }
                    Text("Take a closer look").font(.title3.bold()).foregroundStyle(Palette.ink)
                    VStack(spacing: 14) {
                        Button { create = true } label: {
                            row("Add a property", "Save details and prepare your visit", "building.2.crop.circle", primary: true)
                        }.buttonStyle(.plain)
                        NavigationLink {
                            SavedPropertiesView(properties: properties) { offsets in
                                var values = properties
                                values.remove(atOffsets: offsets)
                                store(values)
                            }
                        } label: {
                            row("Saved properties", "\(properties.count) saved on this device", "square.stack")
                        }.buttonStyle(.plain)
                    }
                    Text("Built for a better-informed property visit.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }.padding(22)
            }
            .background(Palette.background)
            .navigationDestination(for: MediaRoute.self) { route in
                switch route {
                case .recorder: WalkthroughView()
                case .library: PropertyMediaLibrary()
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $create) {
                PrepareProperty { property in store([property] + properties) }
            }
        }.tint(Palette.accent)
    }
    private func row(_ title: String, _ subtitle: String, _ symbol: String, primary: Bool = false) -> some View {
        LensMenuRow(title, subtitle, symbol, primary: primary)
    }
}

struct LensMenuRow: View {
    let title: String
    let subtitle: String
    let symbol: String
    let primary: Bool
    let showsArrow: Bool

    init(_ title: String, _ subtitle: String, _ symbol: String, primary: Bool = false, showsArrow: Bool = true) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self.primary = primary
        self.showsArrow = showsArrow
    }

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(primary ? .white : (symbol == "person.2" ? Palette.coral : Palette.accent))
                .frame(width: 44, height: 44)
                .background(primary ? Color.white.opacity(0.15) : Palette.iconBackground,
                            in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).opacity(0.8)
            }
            Spacer(minLength: 0)
            if showsArrow { Image(systemName: "arrow.up.right").font(.subheadline) }
        }
        .multilineTextAlignment(.leading).padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(RoundedRectangle(cornerRadius: 20))
        .foregroundStyle(primary ? .white : Palette.ink)
        .background(primary ? Palette.primaryAction : Palette.surface, in: RoundedRectangle(cornerRadius: 20))
        .overlay {
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(primary ? .clear : Palette.border, lineWidth: 1)
        }
    }
}

struct LensMenuHeader: View {
    let title: String
    let subtitle: String
    let symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Palette.heroEyebrow)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(.title, design: .serif).weight(.medium))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background(
            LinearGradient(colors: [Palette.heroStart, Palette.heroEnd], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24)
        )
    }
}

struct LensMenuPage<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14, content: content)
                .padding(22)
        }
        .background(Palette.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .tint(Palette.accent)
    }
}

private struct SavedPropertiesView: View {
    let properties: [Property]
    let delete: (IndexSet) -> Void

    var body: some View {
        List {
            LensMenuHeader(title: "Saved properties", subtitle: "Open a property to see its details and walkthroughs.", symbol: "building.2")
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 12, leading: 22, bottom: 10, trailing: 22))

            if properties.isEmpty {
                LensMenuRow("No saved properties", "Prepare a property to save its details here.", "building.2", showsArrow: false)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 22, bottom: 5, trailing: 22))
            }
            ForEach(properties) { property in
                NavigationLink { PropertyDetails(property: property) } label: {
                    LensMenuRow(property.name, "\(property.type) · \(property.location)", "building.2", showsArrow: false)
                }
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 5, leading: 22, bottom: 5, trailing: 22))
            }
            .onDelete(perform: delete)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Palette.background)
        .navigationTitle("Saved properties")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct PrepareProperty: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var location = ""
    @State private var type = "Flat"
    @State private var result: Property?
    let save: (Property) -> Void
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanLocation: String { location.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        NavigationStack {
            Form {
                Section("Property details") {
                    TextField("Property name", text: $name)
                    Picker("Type", selection: $type) {
                        ForEach(["Land", "Flat", "Building"], id: \.self) { Text($0) }
                    }
                    TextField("Area or address", text: $location)
                }
                Section {
                    Label("Capture a property visit", systemImage: "camera")
                    Text("Save the property, then take compass photos, record silent walkthroughs and add room dimensions you have measured.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section {
                    Button("Save property") {
                        let property = Property(name: cleanName, type: type, location: cleanLocation)
                        save(property)
                        result = property
                    }.disabled(cleanName.isEmpty || cleanLocation.isEmpty || result != nil)
                } footer: { Text("Details are saved only on this device.") }
            }
            .navigationTitle("Prepare a property").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .navigationDestination(item: $result) { PropertyDetails(property: $0) }
        }
    }
}

private struct PropertyDetails: View {
    let property: Property
    var body: some View {
        List {
            Section("Property") {
                LabeledContent("Name", value: property.name)
                LabeledContent("Type", value: property.type)
                LabeledContent("Location", value: property.location)
            }
            Section("Tour tools") {
                NavigationLink { WalkthroughView(propertyID: property.id.uuidString) } label: { Label("Record walkthrough with compass", systemImage: "video.circle") }
                NavigationLink { RoomPhotoLibrary(propertyID: property.id.uuidString) } label: {
                    Label("Room photos & dimensions", systemImage: "photo.on.rectangle")
                }
            }
            Section("Saved media") {
                NavigationLink { PropertyMediaLibrary(propertyID: property.id.uuidString) } label: {
                    Label("Property photos & videos", systemImage: "photo.stack")
                }
            }
        }.navigationTitle(property.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct LensSettingsView: View {
    @AppStorage("propertylens.theme.v1") private var theme = "system"
    var body: some View {
        LensMenuPage(title: "Settings") {
            LensMenuHeader(title: "Make it yours", subtitle: "Manage your local profile and choose how MyPropertyVisit looks.", symbol: "gearshape")

            Text("Profile").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            NavigationLink { LocalProfileView() } label: {
                LensMenuRow("Manage local profile", "Edit the name, email and role stored on this device", "person.crop.circle")
            }.buttonStyle(.plain)
            Text("Local profile · No login required")
                .font(.footnote)
                .foregroundStyle(.secondary)

            NavigationLink { LaunchInformationView() } label: {
                LensMenuRow("About & your data", "Offline storage, measurements and exports", "info.circle")
            }.buttonStyle(.plain)

            Text("Appearance").font(.headline).foregroundStyle(Palette.ink).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                Label("Theme", systemImage: "circle.lefthalf.filled").font(.headline).foregroundStyle(Palette.ink)
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                Text("System follows your device appearance.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(20)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(Palette.border) }
        }
    }
}

private struct LocalProfileView: View {
    @AppStorage("propertylens.profile.name") private var storedName = ""
    @AppStorage("propertylens.profile.email") private var storedEmail = ""
    @AppStorage("propertylens.profile.role") private var storedRole = "Buyer"
    @State private var name = ""
    @State private var email = ""
    @State private var role = "Buyer"
    @State private var feedback: String?
    @State private var confirmClear = false
    var body: some View {
        Form {
            Section("Local profile") {
                TextField("Display name (optional)", text: $name)
                    .textContentType(.name)
                TextField("Email (optional, not verified)", text: $email)
                    .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                    .autocorrectionDisabled().textContentType(.emailAddress)
                Picker("Role", selection: $role) {
                    ForEach(["Buyer", "Seller", "Broker"], id: \.self) { Text($0) }
                }
            }
            Section {
                Button("Save profile") {
                    let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard cleanEmail.isEmpty || (cleanEmail.contains("@") && !cleanEmail.contains(" ") && cleanEmail.split(separator: "@").count == 2) else {
                        feedback = "Enter a valid email address or leave it empty."
                        return
                    }
                    storedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    storedEmail = cleanEmail
                    storedRole = role
                    feedback = "Profile saved on this device."
                }
                Button("Clear local profile", role: .destructive) { confirmClear = true }
            } footer: {
                Text("These details do not sign you in or sync to a server. Clearing this profile keeps your saved properties and walkthroughs.")
            }
        }
        .navigationTitle("Local profile").navigationBarTitleDisplayMode(.inline)
        .onAppear { name = storedName; email = storedEmail; role = storedRole }
        .alert("Profile", isPresented: Binding(get: { feedback != nil }, set: { if !$0 { feedback = nil } })) {
            Button("OK") { feedback = nil }
        } message: { Text(feedback ?? "") }
        .confirmationDialog("Clear the local profile? Properties and recordings will be kept.", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear profile", role: .destructive) {
                storedName = ""; storedEmail = ""; storedRole = "Buyer"
                name = ""; email = ""; role = "Buyer"
            }
        }
    }
}


private struct LaunchInformationView: View {
    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0" }
    var body: some View {
        List {
            Section("MyPropertyVisit") {
                LabeledContent("Version", value: version)
                Text("Record property visits, keep compass photos and silent walkthroughs together, and add room details manually. No online account or login is required.")
            }
            Section("Measurements and directions") {
                Text("Dimensions are entered by you, in metres or decimal feet. The area calculation assumes a rectangle. Verify important measurements independently.")
                Text("Compass directions refer to magnetic north and depend on the device's sensors and surroundings. Missing readings are shown as unavailable.")
            }
            Section("Your records stay locally") {
                Text("Properties, your optional profile, capture sessions, room details and media are stored in this app on your device. This version has no app-managed cloud synchronization or complete project backup and restore.")
                Text("Deleting the app or losing your device can result in lost records. Device backups and Photos synchronization are separate services managed through your device settings.")
            }
            Section("What exports include") {
                Text("Shared and saved photos and videos keep the embedded compass. Room dimensions, notes and property/session relationships remain inside MyPropertyVisit; they are not automatically printed over exported media.")
                Text("Saving media to Photos keeps separate media copies. It does not create a full project backup. Export important media before deleting the app.")
            }
            Section("Clearing data") {
                Text("Clearing your local profile keeps properties and media. Deleting a property record does not necessarily delete its captures. Exported or shared copies must be managed separately in their destination.")
            }
        }
        .navigationTitle("About & your data")
        .navigationBarTitleDisplayMode(.inline)
    }
}
