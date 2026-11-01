import SwiftUI
import StudioCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let error = model.setupError {
                SetupMessageView(error: error) { model.resolveTools() }
            } else if model.rootFolder == nil && !model.inPlayground {
                VStack(spacing: 12) {
                    Text("Choose a folder of PlantUML and markdown files").font(.title2)
                    Button("Open Folder…") { model.chooseRoot() }
                    PlaygroundChoices().frame(width: 260).padding(.top, 8)
                }
            } else {
                HSplitView {
                    if model.showSidebar && !model.inPlayground {
                        SidebarView()
                            .frame(minWidth: 180, idealWidth: 240, maxWidth: 400)
                            .background(model.theme.sidebarBackground.ignoresSafeArea())
                    }
                    detail.frame(minWidth: 500)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button { model.theme = model.theme.toggled } label: { Image(systemName: model.theme == .dark ? "sun.max" : "moon") }
                            .help(model.theme == .dark ? "Switch to light theme" : "Switch to dark theme")
                    }
                    if !model.inPlayground {
                        ToolbarItem(placement: .navigation) {
                            Button { model.showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                                .help("Show or hide sidebar")
                                .keyboardShortcut("s", modifiers: [.command, .control])
                        }
                    }
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .preferredColorScheme(model.theme.colorScheme)
        .background(WindowConfigurator())
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
            if let notice = model.notice { banner(notice) }
            if let session = model.session {
                MainView(session: session).id(session.url)
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
