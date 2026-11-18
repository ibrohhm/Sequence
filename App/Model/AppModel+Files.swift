import Foundation
import StudioCore

extension AppModel {

    /// Starts naming a new file or folder in `folder`, else in the focused folder, else in the root.
    func beginNew(_ kind: NewItemKind, in folder: URL? = nil) {
        guard let rootFolder else { notice = "Add a vault first."; return }
        closePlayground()
        showTasks = false
        showFlows = false
        showSidebar = true
        searching = false
        query = ""
        newItem = NewItem(kind: kind, parent: folder ?? LibraryOperations.targetFolder(for: sidebarFocus, root: rootFolder))
    }

    /// Creates the item being named, or drops it when the name is empty.
    func commitNewItem(named name: String) {
        guard let item = newItem else { return }
        newItem = nil
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch item.kind {
        case .file: createFile(named: name, in: item.parent)
        case .folder: createFolder(named: name, in: item.parent)
        }
    }

    func toggleSearch() {
        closePlayground()
        showTasks = false
        showFlows = false
        showSidebar = true
        searching.toggle()
        query = ""
    }

    func createFile(named name: String, in folder: URL?) {
        guard let target = folder ?? rootFolder else { notice = "Open a folder first."; return }
        perform { let url = try LibraryOperations.createFile(named: name, in: target); rescan(); select(url) }
    }

    func createFolder(named name: String, in folder: URL?) {
        guard let target = folder ?? rootFolder else { notice = "Open a folder first."; return }
        perform { _ = try LibraryOperations.createFolder(named: name, in: target); rescan() }
    }

    func rename(_ url: URL, to name: String) {
        perform {
            let renamed = try LibraryOperations.rename(url, to: name)
            rescan()
            if session?.url == url {
                session?.relocate(to: renamed)
                selection = renamed
                defaults.set(renamed.path, forKey: "lastFile")
            }
        }
    }

    /// Moves dropped items from this vault into `folder`; anything outside the vault is ignored.
    func move(_ urls: [URL], into folder: URL) {
        guard let root = rootFolder?.standardizedFileURL.path else { return }
        for url in urls where url.standardizedFileURL.path.hasPrefix(root + "/") {
            perform {
                let moved = try LibraryOperations.move(url, into: folder)
                guard moved != url else { return }
                expansion.remap(from: url.standardizedFileURL.path, to: moved.standardizedFileURL.path)
                if let open = session?.url, let new = LibraryOperations.relocated(open, from: url, to: moved) {
                    session?.relocate(to: new)
                    selection = new
                    defaults.set(new.path, forKey: "lastFile")
                }
                setExpanded(folder, true)
            }
        }
        rescan()
    }

    func delete(_ url: URL) {
        perform {
            try LibraryOperations.delete(url)
            if session?.url.path.hasPrefix(url.path) == true { session = nil; selection = nil }
            rescan()
        }
    }

    func perform(_ work: () throws -> Void) {
        do { try work() } catch LibraryOperationError.alreadyExists { notice = "That name already exists." }
        catch LibraryOperationError.invalidName { notice = "That name is not valid." }
        catch LibraryOperationError.invalidMove { notice = "A folder cannot move into itself." }
        catch { notice = error.localizedDescription }
    }
}
