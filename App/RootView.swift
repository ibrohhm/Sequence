import SwiftUI
import StudioCore

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Group {
            if let error = model.setupError {
                SetupMessageView(error: error) { model.resolveTools() }
            } else if model.rootFolder == nil {
                VStack(spacing: 12) {
                    Text("Choose a folder of PlantUML and markdown files").font(.title2)
                    Button("Open Folder…") { model.chooseRoot() }
                }
            } else {
                NavigationSplitView {
                    SidebarView().navigationSplitViewColumnWidth(min: 180, ideal: 240)
                } detail: {
                    detail
                }
            }
        }
        .frame(minWidth: 900, minHeight: 560)
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
                Text("Select a file").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func banner(_ text: String) -> some View {
        Text(text).font(.callout).frame(maxWidth: .infinity, alignment: .leading).padding(8).background(Color.yellow.opacity(0.2))
    }
}
