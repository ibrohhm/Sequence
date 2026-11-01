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
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 2) {
                ForEach(model.tree) { node in
                    TreeRow(node: node, depth: 0) { menu(for: $0) }
                }
            }
            .padding(8)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { promptText = ""; prompt = .newFile(nil) } label: { Image(systemName: "doc.badge.plus") }.help("New file")
                Button { promptText = ""; prompt = .newFolder(nil) } label: { Image(systemName: "folder.badge.plus") }.help("New folder")
                Spacer()
                Button { model.theme = model.theme.toggled } label: { Image(systemName: model.theme == .dark ? "sun.max" : "moon") }.help(model.theme == .dark ? "Switch to light theme" : "Switch to dark theme")
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

/// One file or folder row with a grey selected state and a lighter grey hover highlight.
private struct TreeRow<Menu: View>: View {
    @EnvironmentObject var model: AppModel
    let node: FileNode
    let depth: Int
    @ViewBuilder let menu: (FileNode) -> Menu
    @State private var expanded = false
    @State private var hovering = false

    private var isSelected: Bool { !node.isDirectory && model.selection == node.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Text(node.name).lineLimit(1)
                } else {
                    Label(node.name, systemImage: "doc.text").lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 5)
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
                        .background(RoundedRectangle(cornerRadius: 6).fill(isSelected ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                if node.isDirectory { withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() } } else { model.select(node.id) }
            }
            .contextMenu { menu(node) }

            if expanded, let children = node.children {
                ForEach(children) { child in
                    TreeRow(node: child, depth: depth + 1, menu: menu)
                }
            }
        }
        .onAppear {
            if let selection = model.selection, selection.path.hasPrefix(node.id.path + "/") { expanded = true }
        }
    }
}
