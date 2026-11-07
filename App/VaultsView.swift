import SwiftUI
import StudioCore

/// The vault control page: switch, add, create, rename, reveal and remove vaults.
struct VaultsView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var creating = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Vaults").font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(model.theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Divider()
            if model.vaults.isEmpty {
                Text("No vaults yet. Create one or add a folder.")
                    .font(.system(size: 13)).foregroundStyle(.secondary).padding(16)
            } else {
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(model.vaults) { vault in
                            VaultRow(vault: vault, active: vault.id == model.activeVault?.id)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 260)
            }
            Divider()
            addSection.padding(16)
        }
        .frame(width: 440)
    }

    @ViewBuilder private var addSection: some View {
        if creating {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Vault name", text: $newName)
                        .textFieldStyle(.roundedBorder).focused($nameFocused).onSubmit(create)
                        .onAppear { nameFocused = true }
                        .onExitCommand { stopCreating() }
                    Button("Create") { create() }.disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Cancel") { stopCreating() }
                }
                Text("Created in ~/Documents/Sequence").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        } else {
            HStack(spacing: 8) {
                Button { creating = true } label: {
                    Label("New vault…", systemImage: "plus").frame(maxWidth: .infinity)
                }
                Button { model.chooseRoot() } label: {
                    Label("Add folder as vault…", systemImage: "folder").frame(maxWidth: .infinity)
                }
            }
            .controlSize(.large)
        }
    }

    private func create() {
        let name = newName
        stopCreating()
        model.createVault(named: name)
    }

    private func stopCreating() {
        creating = false
        newName = ""
    }
}

/// One vault: click to switch; the actions menu shows on hover.
private struct VaultRow: View {
    @EnvironmentObject var model: AppModel
    let vault: Vault
    let active: Bool
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var missing: Bool { !FileManager.default.fileExists(atPath: vault.path) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: active ? "folder.fill" : "folder")
                .foregroundStyle(active ? model.theme.accent : Color.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                if editing {
                    TextField("Name", text: $draft)
                        .textFieldStyle(.roundedBorder).font(.system(size: 13)).focused($draftFocused)
                        .onSubmit(commit).onExitCommand { editing = false }
                        .onAppear { draftFocused = true }
                } else {
                    Text(vault.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                }
                if missing {
                    Text("Folder not found").font(.system(size: 11)).foregroundStyle(.red)
                } else {
                    Text((vault.path as NSString).abbreviatingWithTildeInPath)
                        .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Rename…") { draft = vault.name; editing = true }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([vault.url]) }
                Divider()
                Button("Remove from List") { model.removeVault(vault) }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .opacity(hovering ? 1 : 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 8).fill(active ? model.theme.selectedRow : (hovering ? model.theme.hoverRow : Color.clear)))
        .opacity(missing ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !editing { model.switchVault(vault) } }
    }

    private func commit() {
        model.renameVault(vault, to: draft)
        editing = false
    }
}
