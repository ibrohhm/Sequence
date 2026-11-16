import SwiftUI
import StudioCore

/// Loads the Slack tasks database for the Tasks page and the list pages, and keeps it fresh while the board is open.
@MainActor
final class SlackTasksModel: ObservableObject {
    static let tasksPage = "tasks"

    @Published private(set) var tags: [SlackTag] = []
    @Published private(set) var tasks: [SlackTask] = []
    @Published private(set) var selectedPage: String = UserDefaults.standard.string(forKey: "slackTagSelected") ?? SlackTasksModel.tasksPage
    @Published private(set) var collapsed: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "slackTagsCollapsed") ?? [])
    @Published private(set) var addTagID: String = UserDefaults.standard.string(forKey: "slackAddTag") ?? "todo"
    @Published var showArchived = false
    @Published var notice: String?

    private var store: SlackTaskStore?
    private var lastVersion = -1
    private var polling: Task<Void, Never>?
    private var noticeClear: Task<Void, Never>?
    private var showingError = false

    var isTasksPage: Bool { selectedPage == Self.tasksPage }
    var boardTags: [SlackTag] { tags.filter { $0.kind == .board } }
    var listTags: [SlackTag] { tags.filter { $0.kind == .list } }
    var currentListTag: SlackTag? { isTasksPage ? nil : listTags.first { $0.id == selectedPage } }
    var pages: [(id: String, title: String)] { [(Self.tasksPage, "Tasks")] + listTags.map { ($0.id, $0.name) } }

    var sections: [(tag: SlackTag, columns: [(name: String, tasks: [SlackTask])])] { SlackBoard.sections(tasks, tags: boardTags) }
    var mergedColumns: [(name: String, tasks: [SlackTask])] { SlackBoard.merged(tasks, tags: boardTags) }
    var listCards: [SlackTask] { currentListTag.map { SlackBoard.groups(tasks, for: $0).first?.tasks ?? [] } ?? [] }
    var archivedTasks: [SlackTask] { tasks.filter(\.archived) }
    var hasActiveCards: Bool { tasks.contains { !$0.archived } }

    /// The tag the paste field adds to on the Tasks page: the chosen one, else To-do, else the first board tag.
    var addTag: SlackTag? { boardTags.first { $0.id == addTagID } ?? boardTags.first { $0.id == "todo" } ?? boardTags.first }

    func tagName(_ id: String) -> String? { tags.first { $0.id == id }?.name }

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

    func select(page: String) {
        guard page != selectedPage else { return }
        selectedPage = page
        UserDefaults.standard.set(page, forKey: "slackTagSelected")
        reload()
    }

    func setAddTag(_ id: String) {
        addTagID = id
        UserDefaults.standard.set(id, forKey: "slackAddTag")
    }

    func toggleCollapsed(_ tagID: String) {
        if collapsed.contains(tagID) { collapsed.remove(tagID) } else { collapsed.insert(tagID) }
        let live = Set(tags.map(\.id))
        UserDefaults.standard.set(Array(collapsed.filter { live.contains($0) }).sorted(), forKey: "slackTagsCollapsed")
    }

    func add(_ text: String) {
        guard let link = SlackLink.parse(text) else { return say("That is not a Slack message link.") }
        guard let target = isTasksPage ? addTag?.id : currentListTag?.id else { return say("Add a tag first.") }
        guard openStore() else { return }
        do {
            switch try store!.add(link, tag: target) {
            case .added: break
            case .exists: say("Already on this page.")
            case .restored: say("Restored from archive.")
            }
            reload()
        } catch { fail(error) }
    }

    /// Changes a card's status. In a tag's section (`tag` given) a card from another tag is ignored.
    func move(_ id: String, to column: String, inSection tag: String?) {
        guard let task = tasks.first(where: { $0.id == id }), task.status != column, tag == nil || task.tag == tag else { return }
        write { try $0.setStatus(column, for: id) }
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
            let loaded = try store.tags()
            if !isTasksPage, !loaded.contains(where: { $0.id == selectedPage && $0.kind == .list }) {
                selectedPage = Self.tasksPage
                UserDefaults.standard.set(Self.tasksPage, forKey: "slackTagSelected")
            }
            tags = loaded
            tasks = isTasksPage
                ? try store.tasks(tags: loaded.filter { $0.kind == .board }.map(\.id), includeArchived: true)
                : try store.tasks(tag: selectedPage, includeArchived: true)
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
