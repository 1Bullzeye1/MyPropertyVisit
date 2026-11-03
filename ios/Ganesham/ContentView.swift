import SwiftUI
import UIKit

private struct Property: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: String
    var location: String
}

private enum Palette {
    // Light: indigo and lavender. Dark: slate, ocean blue, and warm sand.
    static let accent = adaptive(0x6250C8, dark: 0x94C7ED)
    static let primaryAction = adaptive(0x6250C8, dark: 0x295C7C)
    static let ink = adaptive(0x25213D, dark: 0xE9EFF5)
    static let background = adaptive(0xF6F5FB, dark: 0x111820)
    static let surface = adaptive(0xFFFFFF, dark: 0x1B2632)
    static let border = adaptive(0xE8E4F3, dark: 0x334352)
    static let iconBackground = adaptive(0xEEEAFB, dark: 0x293B4A)
    static let coral = adaptive(0xBF4257, dark: 0xE6BC92)
    static let heroStart = adaptive(0x282148, dark: 0x233A4B)
    static let heroEnd = adaptive(0x514184, dark: 0x31566A)
    static let heroEyebrow = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(rgb: 0xB6D8EB)
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
    @AppStorage("propertylens.properties.v1") private var saved = "[]"
    @State private var create = false
    @State private var join = false
    private var properties: [Property] {
        (try? JSONDecoder().decode([Property].self, from: Data(saved.utf8))) ?? []
    }
    private func store(_ values: [Property]) {
        if let data = try? JSONEncoder().encode(values), let json = String(data: data, encoding: .utf8) {
            saved = json
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    Label("PropertyLens", systemImage: "viewfinder")
                        .font(.title2.bold()).foregroundStyle(Palette.accent)
                    VStack(alignment: .leading, spacing: 18) {
                        Text("A CLEARER VIEW").font(.caption.weight(.semibold)).tracking(3)
                            .foregroundStyle(Palette.heroEyebrow)
                        Text("Every angle.\nEvery detail.")
                            .font(.system(.largeTitle, design: .serif).weight(.medium))
                        Text("Explore land, flats and buildings with the details that matter.")
                            .foregroundStyle(.white.opacity(0.8))
                        HStack(spacing: 18) {
                            Label("Live tours", systemImage: "video")
                            Label("Directions", systemImage: "safari")
                        }.font(.caption)
                        Label("Measurements", systemImage: "ruler").font(.caption)
                    }
                    .padding(26).frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundStyle(.white)
                    .background(
                        LinearGradient(colors: [Palette.heroStart, Palette.heroEnd],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 26)
                    )
                    NavigationLink { WalkthroughView() } label: {
                        row("Record walkthrough", "Save video with compass readings offline", "video.circle")
                    }.buttonStyle(.plain)
                    Text("Take a closer look").font(.title3.bold()).foregroundStyle(Palette.ink)
                    VStack(spacing: 14) {
                        Button { create = true } label: {
                            row("Start a property call", "Prepare your property for a tour", "video.badge.plus", primary: true)
                        }.buttonStyle(.plain)
                        Button { join = true } label: {
                            row("Join a call", "Enter an invitation code", "person.2")
                        }.buttonStyle(.plain)
                        NavigationLink {
                            List {
                                if properties.isEmpty {
                                    ContentUnavailableView("No saved properties", systemImage: "building.2", description: Text("Prepare a property to save its details here."))
                                }
                                ForEach(properties) { property in
                                    NavigationLink { PropertyDetails(property: property) } label: {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(property.name).font(.headline)
                                            Text("\(property.type) · \(property.location)")
                                                .font(.subheadline).foregroundStyle(.secondary)
                                        }
                                    }
                                }.onDelete { offsets in
                                    var values = properties
                                    values.remove(atOffsets: offsets)
                                    store(values)
                                }
                            }.navigationTitle("Saved properties")
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
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Palette.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $create) {
                PrepareProperty { property in store([property] + properties) }
            }
            .sheet(isPresented: $join) { JoinPropertyCall() }
        }.tint(Palette.accent)
    }
    private func row(_ title: String, _ subtitle: String, _ symbol: String, primary: Bool = false) -> some View {
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
            Image(systemName: "arrow.up.right").font(.subheadline)
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
                    Label("Video calling is coming next", systemImage: "video")
                    Text("Save your property now. Live calls, compass readings and measurement capture are not connected yet.")
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
                Label("Video call · Coming soon", systemImage: "video")
                NavigationLink { WalkthroughView(propertyID: property.id.uuidString) } label: { Label("Record walkthrough with compass", systemImage: "video.circle") }
                Label("Measurements · Coming soon", systemImage: "ruler")
            }
            Section { Text("No measurements have been captured.").foregroundStyle(.secondary) }
        }.navigationTitle(property.name).navigationBarTitleDisplayMode(.inline)
    }
}

private struct JoinPropertyCall: View {
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    var body: some View {
        NavigationStack {
            Form {
                Section("Invitation code") {
                    TextField("Enter a call code", text: $code)
                        .textInputAutocapitalization(.characters).autocorrectionDisabled()
                }
                Section {
                    Label("Call joining is coming soon", systemImage: "video")
                    Text("Live calling is not connected yet. Invitation codes cannot be used at this stage.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Join a property call").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
        }
    }
}
