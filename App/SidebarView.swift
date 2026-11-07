import SwiftUI
import StudioCore

private struct RenamePrompt: Identifiable {
    let url: URL
    var id: String { url.path }
}

struct SidebarView: View {
    @EnvironmentObject var model: AppModel
    @State private var prompt: RenamePrompt?
    @State private var promptText = ""
    @State private var deleteTarget: URL?
    @FocusState private var searchFocused: Bool
    @State private var vaultHover = false

    var body: some View {
        VStack(spacing: 0) {
            header
            if model.searching { searchField }
            ScrollView {
                list.padding(.horizontal, 8).padding(.bottom, 8)
                    .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
                    .contentShape(Rectangle())
                    .onTapGesture { model.sidebarFocus = nil }
            }
        }
        .onChange(of: model.searching) { _, on in searchFocused = on }
        .alert("Rename", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { p in
            TextField("Name", text: $promptText)
            Button("OK") { model.rename(p.url, to: promptText) }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Move to Trash?", isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }), presenting: deleteTarget) { url in
            Button("Move \(url.lastPathComponent) to Trash", role: .destructive) { model.delete(url) }
        }
    }

    private var header: some View {
        HStack {
            Menu {
                ForEach(model.vaults) { vault in
                    Button {
                        model.switchVault(vault)
                    } label: {
                        if vault.id == model.activeVault?.id { Label(vault.name, systemImage: "checkmark") } else { Text(vault.name) }
                    }
                }
                Divider()
                Button("Manage Vaults…") { model.showVaults = true }
                Divider()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill").font(.system(size: 12)).foregroundStyle(model.theme.accent)
                    Text(model.activeVault?.name ?? model.rootFolder?.lastPathComponent ?? "Vault").font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 8).fill(vaultHover ? model.theme.hoverRow : Color.clear))
                .onHover { vaultHover = $0 }
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            Spacer(minLength: 0)
            ChromeIconButton(symbol: "doc.badge.plus", help: "New file", size: 28) { model.beginNew(.file) }
            ChromeIconButton(symbol: "folder.badge.plus", help: "New folder", size: 28) { model.beginNew(.folder) }
        }
        .padding(.horizontal, 8)
        .frame(height: 56)
        .overlay(alignment: .bottom) { Rectangle().fill(model.theme.border).frame(height: 1) }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(.secondary)
            TextField("Search files", text: $model.query)
                .textFieldStyle(.plain).font(.system(size: 13))
                .focused($searchFocused)
                .onExitCommand { model.toggleSearch() }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(model.theme.hoverRow))
        .padding(.horizontal, 12).padding(.bottom, 6)
    }

    @ViewBuilder private var list: some View {
        VStack(alignment: .leading, spacing: 2) {
            if model.query.isEmpty {
                if let item = model.newItem, item.parent.standardizedFileURL.path == model.rootFolder?.standardizedFileURL.path {
                    DraftRow(kind: item.kind)
                }
                ForEach(model.tree.filter { !$0.isDirectory }) { TreeRow(node: $0, depth: 0) { menu(for: $0) } }
                ForEach(model.tree.filter(\.isDirectory)) { TreeRow(node: $0, depth: 0, startsExpanded: true) { menu(for: $0) } }
            } else if matches.isEmpty {
                Text("No matches").font(.system(size: 13)).foregroundStyle(.secondary).padding(.horizontal, 8).padding(.vertical, 6)
            } else {
                ForEach(matches) { TreeRow(node: $0, depth: 0) { menu(for: $0) } }
            }
        }
    }

    private var matches: [FileNode] {
        func files(_ nodes: [FileNode]) -> [FileNode] {
            nodes.flatMap { $0.isDirectory ? files($0.children ?? []) : [$0] }
        }
        return files(model.tree).filter { $0.name.localizedCaseInsensitiveContains(model.query) }
    }

    @ViewBuilder private func menu(for node: FileNode) -> some View {
        if node.isDirectory {
            Button("New File…") { model.beginNew(.file, in: node.id) }
            Button("New Folder…") { model.beginNew(.folder, in: node.id) }
        }
        Button("Copy Name") { copy(node.name) }
        Button("Copy Path") { copy(node.id.path) }
        Divider()
        Button("Rename…") { promptText = node.name; prompt = RenamePrompt(url: node.id) }
        Button("Delete…", role: .destructive) { deleteTarget = node.id }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// One file or folder row with a grey selected state and a lighter grey hover highlight.
private struct TreeRow<Menu: View>: View {
    @EnvironmentObject var model: AppModel
    let node: FileNode
    let depth: Int
    var startsExpanded = false
    @ViewBuilder let menu: (FileNode) -> Menu
    @State private var expanded = false
    @State private var hovering = false

    private var isSelected: Bool { !node.isDirectory && model.selection == node.id }
    private var isFocusedFolder: Bool { node.isDirectory && model.sidebarFocus == node.id }
    private var receivesNewItem: Bool { model.newItem?.parent.standardizedFileURL.path == node.id.standardizedFileURL.path }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if node.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 12)
                    Image(systemName: expanded ? "folder.fill" : "folder").foregroundStyle(.secondary).frame(width: 16)
                    Text(node.name).lineLimit(1)
                } else {
                    Color.clear.frame(width: 12, height: 1)
                    Image(systemName: "doc.text").foregroundStyle(.secondary).frame(width: 16)
                    Text(node.name).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 13))
            .padding(.vertical, 5)
            .padding(.leading, 8 + CGFloat(depth) * 14)
            .padding(.trailing, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? model.theme.selectedRow : (hovering || isFocusedFolder ? model.theme.hoverRow : Color.clear)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture {
                model.sidebarFocus = node.id
                if node.isDirectory { withAnimation(.easeOut(duration: 0.12)) { expanded.toggle() } } else { model.select(node.id) }
            }
            .contextMenu { menu(node) }

            if expanded, let children = node.children {
                VStack(alignment: .leading, spacing: 2) {
                    if let item = model.newItem, receivesNewItem { DraftRow(kind: item.kind, depth: depth + 1) }
                    ForEach(children) { child in
                        TreeRow(node: child, depth: depth + 1, menu: menu)
                    }
                }
                .overlay(alignment: .leading) {
                    Rectangle().fill(model.theme.border).frame(width: 1).padding(.leading, 14 + CGFloat(depth) * 14)
                }
            }
        }
        .onChange(of: model.newItem) { _, item in
            if item?.parent.standardizedFileURL.path == node.id.standardizedFileURL.path { expanded = true }
        }
        .onAppear {
            if startsExpanded || receivesNewItem { expanded = true }
            if let selection = model.selection, selection.path.hasPrefix(node.id.path + "/") { expanded = true }
        }
    }
}

/// A tree row with a text field to name a new file or folder; an empty name drops it.
private struct DraftRow: View {
    @EnvironmentObject var model: AppModel
    let kind: NewItemKind
    var depth = 0
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: 12, height: 1)
            Image(systemName: kind == .folder ? "folder" : "doc.text").foregroundStyle(.secondary).frame(width: 16)
            TextField(kind == .folder ? "Folder name" : "File name", text: $name)
                .textFieldStyle(.plain).focused($focused)
                .onSubmit { model.commitNewItem(named: name) }
                .onExitCommand { model.newItem = nil }
        }
        .font(.system(size: 13))
        .padding(.vertical, 5)
        .padding(.leading, 8 + CGFloat(depth) * 14).padding(.trailing, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(model.theme.hoverRow))
        .onAppear { focused = true }
        .onChange(of: focused) { _, now in
            if !now && model.newItem != nil { model.commitNewItem(named: name) }
        }
    }
}
