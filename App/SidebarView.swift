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
    @State private var searching = false
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if searching { searchField }
            ScrollView {
                list.padding(.horizontal, 8).padding(.bottom, 8)
            }
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

    private var header: some View {
        HStack(spacing: 4) {
            Menu {
                Button("New File…") { promptText = ""; prompt = .newFile(nil) }
                Button("New Folder…") { promptText = ""; prompt = .newFolder(nil) }
                Divider()
                Button("Change Folder…") { model.chooseRoot() }
            } label: {
                HStack(spacing: 4) {
                    Text(model.rootFolder?.lastPathComponent ?? "Folder").font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Spacer(minLength: 0)
            IconButton(symbol: "magnifyingglass", help: "Search files") { toggleSearch() }
            PlaygroundMenu()
            IconButton(symbol: model.theme == .dark ? "sun.max" : "moon", help: model.theme == .dark ? "Switch to light theme" : "Switch to dark theme") {
                model.theme = model.theme.toggled
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Search files", text: $query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { toggleSearch() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(model.theme.hoverRow))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    private func toggleSearch() {
        searching.toggle()
        query = ""
        searchFocused = searching
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if query.isEmpty {
                ActionRow(title: "New file", symbol: "plus") { promptText = ""; prompt = .newFile(nil) }
                ForEach(model.tree.filter { !$0.isDirectory }) { TreeRow(node: $0, depth: 0) { menu(for: $0) } }
                ForEach(model.tree.filter(\.isDirectory)) { section($0) }
            } else if matches.isEmpty {
                Text("No matches").font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 6)
            } else {
                ForEach(matches) { TreeRow(node: $0, depth: 0) { menu(for: $0) } }
            }
        }
    }

    private func section(_ node: FileNode) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(node.name)
                .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                .padding(.leading, 8).padding(.top, 14).padding(.bottom, 2)
                .contextMenu { menu(for: node) }
            ForEach(node.children ?? []) { TreeRow(node: $0, depth: 0) { menu(for: $0) } }
        }
    }

    private var matches: [FileNode] {
        func files(_ nodes: [FileNode]) -> [FileNode] {
            nodes.flatMap { $0.isDirectory ? files($0.children ?? []) : [$0] }
        }
        return files(model.tree).filter { $0.name.localizedCaseInsensitiveContains(query) }
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
            HStack(spacing: 8) {
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Text(node.name).lineLimit(1)
                } else {
                    Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 14)
                    Text(node.name).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
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

/// A plain action row, styled like a tree row.
private struct ActionRow: View {
    @EnvironmentObject var model: AppModel
    let title: String
    let symbol: String
    var selected = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 14)
            Text(title)
            Spacer(minLength: 0)
        }
        .font(.system(size: 13))
        .padding(.vertical, 5).padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
    }
}

/// Header icon that opens one of the two scratch playgrounds.
private struct PlaygroundMenu: View {
    @EnvironmentObject var model: AppModel
    @State private var hovering = false

    var body: some View {
        Menu {
            Button("PlantUML Playground") { model.openPlayground(kind: .diagram) }
            Button("Markdown Playground") { model.openPlayground(kind: .markdown) }
        } label: {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? model.theme.hoverRow : Color.clear))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .onHover { hovering = $0 }
        .help("Open a playground")
    }
}

/// A small icon-only header button with a hover highlight.
private struct IconButton: View {
    @EnvironmentObject var model: AppModel
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .frame(width: 24, height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? model.theme.hoverRow : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
