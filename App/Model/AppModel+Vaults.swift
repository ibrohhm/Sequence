import AppKit
import StudioCore

extension AppModel {
    var vaults: [Vault] { store.vaults }

    /// The vault whose folder is open.
    var activeVault: Vault? { vaults.first { $0.path == rootFolder?.standardizedFileURL.path } }

    func chooseRoot() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use as Vault"
        if panel.runModal() == .OK, let url = panel.url { openRoot(url) }
    }

    func switchVault(_ vault: Vault) {
        guard FileManager.default.fileExists(atPath: vault.path) else { notice = "\(vault.name) is missing from disk."; return }
        openRoot(vault.url)
    }

    func createVault(named name: String) {
        var created: Vault?
        perform {
            try store.update { created = try $0.create(named: name, in: VaultList.defaultBase()) }
        }
        if let created { openRoot(created.url) }
    }

    private func updateVaults(_ change: (inout VaultList) -> Void) {
        do { try store.update(change) } catch { notice = error.localizedDescription }
    }

    func openRoot(_ url: URL) {
        if session?.isDirty == true {
            notice = "Save or discard your changes before switching folders."
            return
        }
        rootFolder = url
        sidebarFocus = nil
        newItem = nil
        expansion = FolderExpansion(states: savedExpansion[url.standardizedFileURL.path] ?? [:])
        defaults.set(url.path, forKey: "rootFolder")
        updateVaults { $0.add(folder: url) }
        store.activePath = url.standardizedFileURL.path
        session = nil
        selection = nil
        rescan()
        watcher?.stop()
        watcher = FolderWatcher(root: url) { [weak self] in
            Task { @MainActor in self?.folderChanged() }
        }
    }

    private var savedExpansion: [String: [String: Bool]] {
        defaults.dictionary(forKey: "folderExpansion") as? [String: [String: Bool]] ?? [:]
    }

    func saveExpansion() {
        guard let root = rootFolder?.standardizedFileURL.path else { return }
        var all = savedExpansion
        all[root] = expansion.states
        defaults.set(all, forKey: "folderExpansion")
    }

    func isExpanded(_ folder: URL, default fallback: Bool) -> Bool {
        expansion.isExpanded(folder.standardizedFileURL.path, default: fallback)
    }

    func setExpanded(_ folder: URL, _ expanded: Bool) {
        expansion.set(folder.standardizedFileURL.path, expanded: expanded)
        saveExpansion()
    }

    func rescan() {
        guard let rootFolder else { tree = []; return }
        tree = (try? LibraryScanner.scan(rootFolder)) ?? []
    }

    private func folderChanged() {
        rescan()
        guard let session else { return }
        switch session.diskDidChange() {
        case .none: break
        case .reloaded: scheduleRender(debounce: false)
        case .conflict: showConflict = true
        case .fileMissing: notice = "\(session.url.lastPathComponent) was deleted or moved. Your text is still in the editor; Save writes it back."
        }
    }
}
