import SwiftUI
import StudioCore

/// The Vaults tab of the Settings window: switch, add, create, rename, reveal and remove vaults.
struct VaultsView: View {
    @ObservedObject private var store = VaultStore.shared
    @State private var creating = false
    @State private var newName = ""
    @FocusState private var nameFocused: Bool

    var body: some View {
        Form {
            Section {
                if store.vaults.isEmpty {
                    Text("No vaults yet. Create one or add a folder.").foregroundStyle(.secondary)
                }
                ForEach(store.vaults) { vault in
                    VaultRow(vault: vault, active: vault.path == store.activePath, enabled: store.hasWindow)
                }
            } header: {
                Text("Your vaults")
            } footer: {
                if !store.hasWindow { Text("Open a Sequence window to switch or add vaults.") }
            }
            Section { addControls }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder private var addControls: some View {
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
                Button { creating = true } label: { Label("New vault…", systemImage: "plus").frame(maxWidth: .infinity) }
                Button { AppModel.active?.chooseRoot() } label: { Label("Add folder as vault…", systemImage: "folder").frame(maxWidth: .infinity) }
            }
            .controlSize(.large)
            .disabled(!store.hasWindow)
        }
    }

    private func create() {
        let name = newName
        stopCreating()
        AppModel.active?.createVault(named: name)
    }

    private func stopCreating() {
        creating = false
        newName = ""
    }
}

/// One vault: click to switch; the actions menu stays faintly visible and strengthens on hover.
private struct VaultRow: View {
    @ObservedObject private var store = VaultStore.shared
    @AppStorage("theme") private var themeName = "light"
    let vault: Vault
    let active: Bool
    let enabled: Bool
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var draftFocused: Bool

    private var theme: Theme { Theme(rawValue: themeName) ?? .light }
    private var missing: Bool { !FileManager.default.fileExists(atPath: vault.path) }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: active ? "folder.fill" : "folder")
                .foregroundStyle(active ? theme.accent : Color.secondary).frame(width: 18)
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
                Button("Remove from List") { try? store.update { $0.remove(vault.id) } }
            } label: {
                Image(systemName: "ellipsis").foregroundStyle(.secondary).frame(width: 26, height: 26)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .opacity(hovering ? 1 : 0.4)
        }
        .padding(.vertical, 2)
        .opacity(missing ? 0.6 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { if !editing && enabled { AppModel.active?.switchVault(vault) } }
    }

    private func commit() {
        try? store.update { $0.rename(vault.id, to: draft) }
        editing = false
    }
}
