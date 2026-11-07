import SwiftUI
import StudioCore

/// App information shown by the gear icon and ⌘,.
struct AboutView: View {
    @AppStorage("theme") private var theme = "light"
    @State private var java = "Checking…"

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    private var plantUMLVersion: String {
        guard let url = Bundle.main.url(forResource: "PLANTUML_VERSION", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Unknown" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
                    Text("Sequence").font(.system(size: 20, weight: .semibold))
                    Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("View and edit PlantUML diagrams and markdown from a folder.")
                        .font(.system(size: 13)).multilineTextAlignment(.center).padding(.top, 4)
                }
                .frame(maxWidth: .infinity)
            }
            Section {
                row("PlantUML", plantUMLVersion)
                row("Java", java)
            }
        }
        .formStyle(.grouped)
        .preferredColorScheme((Theme(rawValue: theme) ?? .light).colorScheme)
        .task { resolve() }
    }

    private func row(_ name: String, _ value: String) -> some View {
        LabeledContent(name) {
            Text(value).textSelection(.enabled).lineLimit(2).multilineTextAlignment(.trailing)
        }
        .font(.system(size: 12))
    }

    private func resolve() {
        let resources = Bundle.main.resourceURL
        let locator = ToolLocator(searchDirs: ToolLocator.bundledDirs(in: resources) + ToolLocator.defaultDirs)
        if let url = try? locator.java() {
            java = url.path.hasPrefix(resources?.path ?? "\u{0}") ? "Bundled runtime" : "System: \(url.path)"
        } else {
            java = "Not found"
        }
    }
}
