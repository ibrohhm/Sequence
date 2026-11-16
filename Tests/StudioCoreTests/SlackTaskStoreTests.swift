import Foundation
import SQLite3
import Testing
@testable import StudioCore

@Suite struct SlackTaskStoreTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-15T10:00:00Z")!
    let rootLink = SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929")!
    let otherLink = SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794545000000200")!
    let replyLink = SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929")!

    let v1DDL = """
    CREATE TABLE tasks (channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
      replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT,
      status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
      archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, thread_ts));
    """
    let v2DDL = """
    CREATE TABLE tasks (channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
      replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT, summary TEXT, next_action TEXT, summary_replies INTEGER,
      status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
      archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, thread_ts));
    """

    func tempPath() -> String {
        NSTemporaryDirectory() + "slack-\(UUID().uuidString)/nested/slack-tasks.db"
    }

    func prepareFolder(_ path: String) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
    }

    /// Plays the part of the sync tool: a second connection to the same file.
    func raw(_ path: String, _ sql: String) {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    func rawText(_ path: String, _ sql: String) -> String {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return "" }
        return String(cString: text)
    }

    func review(columns: [String] = ["Open", "Waiting", "Done"]) -> SlackTag {
        SlackTag(id: "review", name: "Review", kind: .board, slackList: .none, reactions: ["eyes"], columns: columns, position: 0, builtin: false)
    }

    @Test func initCreatesFolderFileAndSettings() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(rawText(path, "PRAGMA user_version") == "3")
        #expect(rawText(path, "PRAGMA journal_mode") == "wal")
        #expect(try store.tags().map(\.id) == ["todo", "saved"])
        _ = try SlackTaskStore(path: path)
        #expect(try store.tags().count == 2)
    }

    @Test func seedsAreTheBuiltInTodoBoardAndSavedList() throws {
        let tags = try SlackTaskStore(path: tempPath()).tags()
        #expect(tags[0] == SlackTag(id: "todo", name: "To-do", kind: .board, slackList: .todo, reactions: ["loading", "loading1"],
                                    columns: ["Todo", "In progress", "Blocked", "Done"], position: 0, builtin: true))
        #expect(tags[1] == SlackTag(id: "saved", name: "Saved", kind: .list, slackList: .saved, reactions: [], columns: [], position: 1, builtin: true))
    }

    @Test func upgradesAV2DatabaseWithCardsIntoTheTodoTag() throws {
        let path = tempPath()
        try prepareFolder(path)
        raw(path, v2DDL + """
        INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status, summary, summary_replies, replies) VALUES ('C', '1.1', 'p', '2026-11-15', 'blocked', 'Waiting on vendor.', 2, 2);
        INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status, archived) VALUES ('C', '2.2', 'p', '2026-11-15', 'done', 1);
        INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C', '3.3', 'p', '2026-11-15', 'inprogress');
        PRAGMA user_version = 2;
        """)
        let store = try SlackTaskStore(path: path)
        let tasks = try store.tasks(tag: "todo", includeArchived: true).sorted { $0.threadTS < $1.threadTS }
        #expect(tasks.map(\.status) == ["Blocked", "Done", "In progress"])
        #expect(tasks.map(\.archived) == [false, true, false])
        #expect(tasks[0].summary == "Waiting on vendor." && tasks[0].summaryReplies == 2)
        #expect(rawText(path, "PRAGMA user_version") == "3")
        #expect(try store.tags().count == 2)
        _ = try SlackTaskStore(path: path)
    }

    @Test func upgradesAV1DatabaseThroughV2() throws {
        let path = tempPath()
        try prepareFolder(path)
        raw(path, v1DDL + """
        INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C', '1.1', 'p', '2026-11-15', 'blocked');
        PRAGMA user_version = 1;
        """)
        let store = try SlackTaskStore(path: path)
        let task = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(task.status == "Blocked")
        #expect(task.summary == nil && task.nextAction == nil && task.summaryReplies == nil)
        #expect(rawText(path, "PRAGMA user_version") == "3")
    }

    @Test func addInsertsAPastedLinkInTheFirstColumnWithoutFacts() throws {
        let store = try SlackTaskStore(path: tempPath())
        #expect(try store.add(rootLink, tag: "todo", now: now) == .added)
        let task = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(task.status == "Todo")
        #expect(!task.archived)
        #expect(task.tagged == "2026-11-15")
        #expect(task.permalink == rootLink.permalink)
        #expect(task.channelName == nil && task.snippet == nil && task.replies == nil && task.repliesAtTag == nil && task.lastReply == nil)
    }

    @Test func aListCardHasAnEmptyStatus() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, tag: "saved", now: now)
        #expect(try store.tasks(tag: "saved", includeArchived: false).first?.status == "")
    }

    @Test func addingToAnUnknownTagFails() throws {
        let store = try SlackTaskStore(path: tempPath())
        #expect(throws: SlackStoreError.self) { try store.add(rootLink, tag: "nope", now: now) }
    }

    @Test func addingTwiceExistsAndAnArchivedOneIsRestored() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, tag: "todo", now: now)
        #expect(try store.add(rootLink, tag: "todo", now: now) == .exists)
        let id = try #require(try store.tasks(tag: "todo", includeArchived: false).first).id
        try store.setArchived(true, for: id)
        #expect(try store.tasks(tag: "todo", includeArchived: false).isEmpty)
        #expect(try store.add(rootLink, tag: "todo", now: now) == .restored)
        #expect(try store.tasks(tag: "todo", includeArchived: false).count == 1)
    }

    @Test func aReplyLinkIsKeyedToTheThreadRoot() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(replyLink, tag: "todo", now: now)
        #expect(try store.tasks(tag: "todo", includeArchived: false).first?.threadTS == "1794536057.965929")
    }

    @Test func theSameThreadInTwoTagsIsTwoIndependentCards() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, tag: "todo", now: now)
        _ = try store.add(rootLink, tag: "saved", now: now)
        let todo = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        try store.setStatus("Blocked", for: todo.id)
        try store.setArchived(true, for: "saved/C07R08WFC81/1794536057.965929")
        #expect(try store.tasks(tag: "todo", includeArchived: false).first?.status == "Blocked")
        #expect(try store.tasks(tag: "todo", includeArchived: false).first?.archived == false)
        #expect(try store.tasks(tag: "saved", includeArchived: false).isEmpty)
    }

    @Test func setStatusChangesOnlyTheStatus() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, tag: "todo", now: now)
        let before = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        try store.setStatus("Blocked", for: before.id)
        var after = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(after.status == "Blocked")
        after.status = before.status
        #expect(after == before)
    }

    @Test func decodesARowWrittenTheWaySyncWritesIt() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        raw(path, """
        INSERT INTO tasks (tag, channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced, status)
        VALUES ('todo', 'C07R08WFC81', '1794536057.965929', 'https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929',
                'agent-network-eng', 'Store internal_account_number', 12, 10, '2026-11-13T02:14:17Z', '2026-11-13', '2026-11-15T10:00:00Z', 'Todo')
        """)
        let task = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(task.channelName == "agent-network-eng")
        #expect(task.replies == 12 && task.repliesAtTag == 10 && task.newReplies == 2)
        #expect(task.lastReply == ISO8601DateFormatter().date(from: "2026-11-13T02:14:17Z"))
    }

    @Test func statusAndSyncFactsSurviveEachOthersWrites() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        _ = try store.add(rootLink, tag: "todo", now: now)
        let id = try #require(try store.tasks(tag: "todo", includeArchived: false).first).id
        try store.setStatus("In progress", for: id)
        raw(path, "UPDATE tasks SET replies = 5, last_reply = '2026-11-14T01:00:00Z'")
        var task = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(task.status == "In progress" && task.replies == 5)
        raw(path, "UPDATE tasks SET replies = 6")
        try store.setStatus("Done", for: id)
        task = try #require(try store.tasks(tag: "todo", includeArchived: false).first)
        #expect(task.status == "Done" && task.replies == 6)
    }

    @Test func dataVersionChangesWhenAnotherConnectionWrites() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        let before = try store.dataVersion()
        raw(path, "INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged) VALUES ('todo','C','1.1','p','2026-11-15')")
        #expect(try store.dataVersion() != before)
    }

    @Test func defaultPathHonoursTheEnvOverride() {
        let saved = ProcessInfo.processInfo.environment["SEQUENCE_SLACK_DB"]
        defer { if let saved { setenv("SEQUENCE_SLACK_DB", saved, 1) } else { unsetenv("SEQUENCE_SLACK_DB") } }
        setenv("SEQUENCE_SLACK_DB", "/tmp/custom.db", 1)
        #expect(SlackTaskStore.defaultPath() == "/tmp/custom.db")
        unsetenv("SEQUENCE_SLACK_DB")
        #expect(SlackTaskStore.defaultPath().hasSuffix("Application Support/Sequence/slack-tasks.db"))
    }

    @Test func saveTagAddsACustomTagAfterTheSeeds() throws {
        let store = try SlackTaskStore(path: tempPath())
        try store.saveTag(review())
        let tags = try store.tags()
        #expect(tags.map(\.id) == ["todo", "saved", "review"])
        #expect(tags[2].position == 2 && tags[2].reactions == ["eyes"] && tags[2].columns == ["Open", "Waiting", "Done"] && !tags[2].builtin)
    }

    @Test func saveTagRejectsInvalidInputBeforeTouchingAnything() throws {
        let store = try SlackTaskStore(path: tempPath())
        #expect(throws: SlackStoreError.self) { try store.saveTag(review(columns: [])) }
        #expect(try store.tags().count == 2)
    }

    @Test func renamingAndRemovingColumnsMovesCardsInTheSameSave() throws {
        let store = try SlackTaskStore(path: tempPath())
        try store.saveTag(review())
        _ = try store.add(rootLink, tag: "review", now: now)
        _ = try store.add(otherLink, tag: "review", now: now)
        let ids = try store.tasks(tag: "review", includeArchived: false).map(\.id)
        let waiting = try #require(ids.first)
        try store.setStatus("Waiting", for: waiting)
        try store.setStatus("Done", for: try #require(ids.last))
        var edited = review(columns: ["Open", "Blocked"])
        edited.name = "Review"
        try store.saveTag(edited, renames: ["Waiting": "Blocked"])
        let byID = Dictionary(uniqueKeysWithValues: try store.tasks(tag: "review", includeArchived: false).map { ($0.id, $0.status) })
        #expect(byID[waiting] == "Blocked")
        #expect(byID[try #require(ids.last)] == "Open")
    }

    @Test func deletingACustomTagKeepsItsCardsAndRecreatingShowsThemAgain() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        try store.saveTag(review())
        _ = try store.add(rootLink, tag: "review", now: now)
        try store.deleteTag("review")
        #expect(try store.tags().map(\.id) == ["todo", "saved"])
        #expect(rawText(path, "SELECT COUNT(*) FROM tasks WHERE tag = 'review'") == "1")
        try store.saveTag(review())
        #expect(try store.tasks(tag: "review", includeArchived: false).count == 1)
    }

    @Test func aBuiltInTagCannotBeDeletedOrChangeKind() throws {
        let store = try SlackTaskStore(path: tempPath())
        #expect(throws: SlackStoreError.self) { try store.deleteTag("todo") }
        var todo = try #require(try store.tags().first)
        todo.kind = .list
        todo.slackList = .none
        todo.name = "Mine"
        todo.columns = ["A"]
        try store.saveTag(todo)
        let saved = try #require(try store.tags().first)
        #expect(saved.kind == .board && saved.slackList == .todo && saved.name == "Mine" && saved.columns == ["A"])
    }

    @Test func moveTagReordersWithoutGaps() throws {
        let store = try SlackTaskStore(path: tempPath())
        try store.saveTag(review())
        try store.moveTag("review", to: 0)
        let tags = try store.tags()
        #expect(tags.map(\.id) == ["review", "todo", "saved"])
        #expect(tags.map(\.position) == [0, 1, 2])
    }
}
