import SwiftUI
import StudioCore

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @AppStorage("sidebarWidth") private var sidebarWidth = 236.0
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let error = model.setupError {
                SetupMessageView(error: error) { model.resolveTools() }
            } else if model.rootFolder == nil && !model.inPlayground {
                VStack(spacing: 12) {
                    Text("Choose a vault of PlantUML and markdown files").font(.title2)
                    Button("Add Folder as Vault…") { model.chooseRoot() }
                    Button("Manage Vaults…") { openWindow(id: "vaults") }
                    PlaygroundChoices().frame(width: 260).padding(.top, 8)
                }
            } else {
                HStack(spacing: 0) {
                    IconRail().zIndex(1)
                    HStack(spacing: 8) {
                        if model.showSidebar && !model.inPlayground {
                            SidebarView().frame(width: sidebarWidth).panel(model.theme, fill: model.theme.sidebarBackground)
                                .overlay(alignment: .trailing) { SidebarResizer(width: $sidebarWidth).offset(x: 8) }
                        }
                        detail.panel(model.theme, fill: model.theme.panelBackground)
                    }
                    .padding(.trailing, 8).padding(.vertical, 8)
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .background(model.theme.frameBackground)
        .preferredColorScheme(model.theme.colorScheme)
        .background(WindowConfigurator(theme: model.theme))
        .alert("Unsaved changes", isPresented: Binding(get: { model.pendingSelection != nil }, set: { if !$0 { model.cancelPendingSelection() } })) {
            Button("Save") { model.resolvePendingSelection(save: true) }
            Button("Discard", role: .destructive) { model.resolvePendingSelection(save: false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(model.session?.url.lastPathComponent ?? "This file") has edits that are not saved.")
        }
        .alert("File changed on disk", isPresented: $model.showConflict) {
            Button("Reload from disk") { model.reloadFromDisk() }
            Button("Keep my edits", role: .cancel) { model.session?.keepMine() }
        } message: {
            Text("\(model.session?.url.lastPathComponent ?? "This file") changed outside the app and you have unsaved edits.")
        }
    }

    private var detail: some View {
        VStack(spacing: 0) {
            if let session = model.session { PageHeader(session: session) }
            if let notice = model.notice { banner(notice) }
            if let session = model.session {
                MainView(session: session).id(session.url)
                PromptBar(kind: DocumentKind(url: session.url))
            } else {
                VStack(spacing: 20) {
                    Text("Select a file").font(.system(size: 15, weight: .medium)).foregroundStyle(.secondary)
                    PlaygroundChoices().frame(width: 260)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color.yellow.opacity(0.2))
    }
}

/// The two playground entry rows, styled like sidebar rows.
private struct PlaygroundChoices: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Or start a playground").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                .padding(.horizontal, 8).padding(.bottom, 4)
            row("PlantUML", symbol: "square.and.pencil", shortcut: "⌘⇧P") { model.openPlayground(kind: .diagram) }
            row("Markdown", symbol: "doc.text", shortcut: "⌘⇧M") { model.openPlayground(kind: .markdown) }
        }
    }

    private func row(_ title: String, symbol: String, shortcut: String, action: @escaping () -> Void) -> some View {
        PlaygroundRow(title: title, symbol: symbol, shortcut: shortcut, action: action)
    }
}

private struct PlaygroundRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let symbol: String
    let shortcut: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 14)
            Text(title)
            Spacer(minLength: 0)
            Text(shortcut).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .font(.system(size: 13))
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? model.theme.hoverRow : Color.clear))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

private extension View {
    /// A rounded, bordered panel sitting on the window frame.
    func panel(_ theme: Theme, fill: Color) -> some View {
        background(fill)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(theme.border))
    }
}

/// A drag handle in the gap right of the sidebar that sets its width.
private struct SidebarResizer: View {
    @Binding var width: Double
    @EnvironmentObject var model: AppModel
    @State private var startWidth: Double?
    @State private var hovering = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1).fill(hovering || startWidth != nil ? model.theme.accent.opacity(0.7) : Color.clear)
            .frame(width: 2)
            .frame(width: 8)
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        width = min(480, max(180, start + drag.translation.width))
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}
