import SwiftUI

struct SettingsView: View {
    @AppStorage("javaPath") private var javaPath = ""
    @AppStorage("dotPath") private var dotPath = ""
    @AppStorage("theme") private var theme = "light"

    var body: some View {
        Form {
            TextField("Java path (blank = auto)", text: $javaPath)
            TextField("Graphviz dot path (blank = auto)", text: $dotPath)
            Button("Apply") { NotificationCenter.default.post(name: .toolPathsChanged, object: nil) }
        }
        .padding(20)
        .frame(width: 460)
        .preferredColorScheme((Theme(rawValue: theme) ?? .light).colorScheme)
    }
}
