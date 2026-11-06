import SwiftUI
import StudioCore

/// App information shown by the gear icon and ⌘,.
struct AboutView: View {
    @AppStorage("theme") private var theme = "light"
    @State private var java = "Checking…"
    @State private var graphviz = "Checking…"
    @State private var claude = "Checking…"

    private var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev" }

    private var plantUMLVersion: String {
        guard let url = Bundle.main.url(forResource: "PLANTUML_VERSION", withExtension: nil),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "Unknown" }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 72, height: 72)
            Text("Sequence").font(.system(size: 20, weight: .semibold))
            Text("Version \(version)").font(.system(size: 12)).foregroundStyle(.secondary)
            Text("View and edit PlantUML diagrams and markdown from a folder.")
                .font(.system(size: 13)).multilineTextAlignment(.center).padding(.top, 6)
            Divider().padding(.vertical, 12)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                row("PlantUML", plantUMLVersion)
                row("Java", java)
                row("Graphviz", graphviz)
                row("Claude Code", claude)
            }
        }
        .padding(24)
        .frame(width: 420)
        .preferredColorScheme((Theme(rawValue: theme) ?? .light).colorScheme)
        .task { resolve() }
    }

    private func row(_ name: String, _ value: String) -> some View {
        GridRow {
            Text(name).foregroundStyle(.secondary)
            Text(value).textSelection(.enabled).lineLimit(2)
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
        claude = (try? ToolLocator(searchDirs: ToolLocator.claudeDirs).claude())?.path ?? "Not found (the AI prompt is unavailable)"
        graphviz = (try? locator.dot())?.path ?? "Not installed (using the built-in layout engine)"
    }
}
