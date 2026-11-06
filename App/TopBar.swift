import SwiftUI
import StudioCore

/// The bar above the detail pane: breadcrumb on the left; search, theme, mode switch and save on the right.
struct TopBar: View {
    @EnvironmentObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Breadcrumb(session: model.session)
            Spacer(minLength: 12)
            if model.session != nil { findField }
            ChromeIconButton(
                symbol: model.theme == .dark ? "sun.max" : "moon",
                help: model.theme == .dark ? "Switch to light theme" : "Switch to dark theme",
                size: 32
            ) { model.theme = model.theme.toggled }
            if let session = model.session { SessionControls(session: session) }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .onChange(of: model.findQuery) { _, query in model.find(query) }
    }

    private var findField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
            TextField("Find in file", text: $model.findQuery)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .onSubmit { model.find(model.findQuery, advance: true); searchFocused = true }
                .onExitCommand { model.findQuery = ""; searchFocused = false }
            Text("⌘K").font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.horizontal, 5).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 4).fill(model.theme.hoverRow))
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 32)
        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.panelBackground))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.border))
        .background(Button("") { searchFocused = true }.keyboardShortcut("k").frame(width: 0, height: 0).opacity(0))
    }
}

/// Subfolders > file (relative to the opened folder), or Playground > language.
private struct Breadcrumb: View {
    @EnvironmentObject var model: AppModel
    let session: DocumentSession?

    private var parts: [String] {
        if model.inPlayground { return ["Playground", model.playgroundKind == .markdown ? "Markdown" : "PlantUML"] }
        guard let root = model.rootFolder else { return [] }
        guard let url = session?.url else { return [] }
        let prefix = root.path + "/"
        let relative = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.lastPathComponent
        return relative.split(separator: "/").map(String.init)
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, name in
                if index > 0 { Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary) }
                if index == parts.count - 1 {
                    HStack(spacing: 4) {
                        Text(name).font(.system(size: 14, weight: .medium)).lineLimit(1)
                        if let session, !model.inPlayground { DirtyDot(session: session) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: 7).fill(model.theme.hoverRow))
                } else {
                    Text(name).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

private struct DirtyDot: View {
    @ObservedObject var session: DocumentSession

    var body: some View {
        if session.isDirty { Circle().fill(Color.secondary).frame(width: 6, height: 6) }
    }
}

/// Mode switch and Save for a file; Save to folder for a playground.
private struct SessionControls: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        if model.inPlayground {
            Button { model.saveCopyOfPlayground() } label: {
                Text("Save to folder…").font(.system(size: 13, weight: .medium))
                    .padding(.horizontal, 14).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.panelBackground))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(model.theme.border))
            }
            .buttonStyle(.plain)
        } else {
            ModeSwitch()
            Button { model.save() } label: {
                Text("Save").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(session.isDirty ? Color.white : Color.secondary)
                    .padding(.horizontal, 16).frame(height: 32)
                    .background(RoundedRectangle(cornerRadius: 8).fill(session.isDirty ? model.theme.accent : model.theme.hoverRow))
            }
            .buttonStyle(.plain)
            .disabled(!session.isDirty)
        }
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
        HStack(spacing: 2) {
            ForEach(modes, id: \.symbol) { item in
                ChromeIconButton(symbol: item.symbol, help: item.help, size: 28, selected: model.mode == item.mode) { model.mode = item.mode }
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 11).fill(model.theme.hoverRow))
    }
}
