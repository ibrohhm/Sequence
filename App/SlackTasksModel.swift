import SwiftUI
import StudioCore

/// Loads the Slack tasks database for the board and keeps it fresh while the board is open.
@MainActor
final class SlackTasksModel: ObservableObject {
    @Published private(set) var tasks: [SlackTask] = []
    @Published var showArchived = false
    @Published var notice: String?

    private var store: SlackTaskStore?
    private var lastVersion = -1
    private var polling: Task<Void, Never>?
    private var noticeClear: Task<Void, Never>?
    private var showingError = false

    var columns: [SlackStatus: [SlackTask]] { SlackBoard.columns(tasks) }
    var archivedTasks: [SlackTask] { tasks.filter(\.archived) }

    func start() {
        guard polling == nil else { return }
        openStore()
        reload()
        polling = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                self?.poll()
            }
        }
    }

    func stop() {
        polling?.cancel()
        polling = nil
    }

    func add(_ text: String) {
        guard let link = SlackLink.parse(text) else { return say("That is not a Slack message link.") }
        guard openStore() else { return }
        do {
            switch try store!.add(link) {
            case .added: break
            case .exists: say("Already on the board.")
            case .restored: say("Restored from archive.")
            }
            reload()
        } catch { fail(error) }
    }

    func move(_ id: String, to status: SlackStatus) {
        guard let task = tasks.first(where: { $0.id == id }), task.status != status else { return }
        write { try $0.setStatus(status, for: id) }
    }

    func archive(_ id: String) { write { try $0.setArchived(true, for: id) } }
    func restore(_ id: String) { write { try $0.setArchived(false, for: id) } }

    private func write(_ change: (SlackTaskStore) throws -> Void) {
        guard openStore() else { return }
        do {
            try change(store!)
            reload()
        } catch { fail(error) }
    }

    @discardableResult private func openStore() -> Bool {
        if store != nil { return true }
        do {
            store = try SlackTaskStore()
            return true
        } catch {
            fail(error)
            return false
        }
    }

    private func poll() {
        guard let store else { return openStore() ? reload() : () }
        do {
            let version = try store.dataVersion()
            if version != lastVersion || showingError { reload() }
        } catch { fail(error) }
    }

    private func reload() {
        guard let store else { return }
        do {
            let version = try store.dataVersion()
            tasks = try store.tasks(includeArchived: true)
            lastVersion = version
            if showingError { notice = nil; showingError = false }
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        noticeClear?.cancel()
        showingError = true
        notice = error.localizedDescription
    }

    private func say(_ text: String) {
        notice = text
        showingError = false
        noticeClear?.cancel()
        noticeClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { self?.notice = nil }
        }
    }
}
