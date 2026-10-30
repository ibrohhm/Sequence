import SwiftUI
import StudioCore

private enum Prompt: Identifiable {
    case newFile(URL?), newFolder(URL?), rename(URL)
    var id: String {
        switch self {
        case .newFile(let u): "file-\(u?.path ?? "")"
        case .newFolder(let u): "folder-\(u?.path ?? "")"
        case .rename(let u): "rename-\(u.path)"
        }
    }
    var title: String {
        switch self { case .newFile: "New file"; case .newFolder: "New folder"; case .rename: "Rename" }
    }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var prompt: Prompt?
    @State private var promptText = ""
    @State private var deleteTarget: URL?

    var body: some View {
        List(model.tree, children: \.children, selection: Binding(get: { model.selection }, set: { model.select($0) })) { node in
            Label(node.name, systemImage: node.isDirectory ? "folder" : "doc.text")
                .contextMenu { menu(for: node) }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { promptText = ""; prompt = .newFile(nil) } label: { Image(systemName: "doc.badge.plus") }.help("New file")
                Button { promptText = ""; prompt = .newFolder(nil) } label: { Image(systemName: "folder.badge.plus") }.help("New folder")
                Spacer()
                Button { model.chooseRoot() } label: { Image(systemName: "folder") }.help("Change root folder")
            }
            .buttonStyle(.borderless).padding(8)
        }
        .alert(prompt?.title ?? "", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { p in
            TextField("Name", text: $promptText)
            Button("OK") { run(p) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Move to Trash?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { url in
            Button("Move \(url.lastPathComponent) to Trash", role: .destructive) { model.delete(url) }
        }
    }

    @ViewBuilder private func menu(for node: FileNode) -> some View {
        if node.isDirectory {
            Button("New File…") { promptText = ""; prompt = .newFile(node.id) }
            Button("New Folder…") { promptText = ""; prompt = .newFolder(node.id) }
        }
        Button("Rename…") { promptText = node.name; prompt = .rename(node.id) }
        Button("Delete…", role: .destructive) { deleteTarget = node.id }
    }

    private func run(_ p: Prompt) {
        switch p {
        case .newFile(let folder): model.createFile(named: promptText, in: folder)
        case .newFolder(let folder): model.createFolder(named: promptText, in: folder)
        case .rename(let url): model.rename(url, to: promptText)
        }
    }
}
