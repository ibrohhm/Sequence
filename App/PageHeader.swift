import SwiftUI
import StudioCore

/// The header of the detail panel: file name and folder on the left; find, mode switch and save on the right.
struct PageHeader: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession
    @FocusState private var findFocused: Bool
    @State private var findOpen = false

    private var title: String {
        guard model.inPlayground else { return session.url.lastPathComponent }
        return model.playgroundKind == .markdown ? "Markdown Playground" : "PlantUML Playground"
    }

    private var subtitle: String {
        guard !model.inPlayground else { return "Scratch editor, remembered between launches" }
        guard let root = model.rootFolder else { return session.url.deletingLastPathComponent().lastPathComponent }
        let folder = session.url.deletingLastPathComponent().path
        let prefix = root.path + "/"
        return folder.hasPrefix(prefix) ? root.lastPathComponent + "/" + String(folder.dropFirst(prefix.count)) : root.lastPathComponent
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(title).font(.system(size: 16, weight: .semibold)).lineLimit(1)
                        if !model.inPlayground { DirtyDot(session: session) }
                    }
                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
                .contextMenu {
                    if !model.inPlayground {
                        Button("Copy Name") { copy(session.url.lastPathComponent) }
                        Button("Copy Path") { copy(session.url.path) }
                    }
                }
                Spacer(minLength: 12)
                if findOpen { findField } else { ChromeIconButton(symbol: "magnifyingglass", help: "Find in file (⌘F)", size: 28) { openFind() } }
                if model.inPlayground {
                    Button { model.saveCopyOfPlayground() } label: {
                        Text("Save to folder…").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14).frame(height: 28)
                            .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.panelBackground))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.border))
                    }
                    .buttonStyle(.plain)
                } else {
                    ModeSwitch()
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            Rectangle().fill(model.theme.border).frame(height: 1)
        }
        .onChange(of: model.findQuery) { _, query in model.find(query) }
        .onChange(of: model.findFocusTick) { _, _ in openFind() }
        .onChange(of: findFocused) { _, focused in
            if !focused && model.findQuery.isEmpty { findOpen = false }
        }
    }

    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Find in file", text: $model.findQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($findFocused)
                .onSubmit { model.find(model.findQuery, advance: true); findFocused = true }
                .onExitCommand { model.findQuery = ""; findFocused = false; findOpen = false }
        }
        .padding(.horizontal, 10)
        .frame(width: 200, height: 28)
        .onAppear { findFocused = true }
        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.border))
    }

    private func openFind() {
        findOpen = true
        findFocused = true
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct DirtyDot: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        if session.isDirty { Circle().fill(model.theme.accent).frame(width: 7, height: 7) }
    }
}

private struct ModeSwitch: View {
    @EnvironmentObject var model: AppModel

    private let modes: [(mode: ViewMode, symbol: String, help: String)] = [
        (.view, "eye", "View"),
        (.edit, "pencil", "Edit"),
        (.editPreview, "rectangle.split.2x1", "Edit with preview"),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(modes, id: \.symbol) { item in
                ChromeIconButton(symbol: item.symbol, help: item.help, size: 28, selected: model.mode == item.mode) { model.mode = item.mode }
            }
        }
    }
}
