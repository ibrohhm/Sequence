import Foundation
import SQLite3
import Testing
@testable import StudioCore

@Suite struct SlackTaskStoreTests {
    let now = ISO8601DateFormatter().date(from: "2026-11-15T10:00:00Z")!
    let rootLink = SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929")!
    let replyLink = SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929")!

    func tempPath() -> String {
        NSTemporaryDirectory() + "slack-\(UUID().uuidString)/nested/slack-tasks.db"
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

    @Test func initCreatesFolderFileAndSettings() throws {
        let path = tempPath()
        _ = try SlackTaskStore(path: path)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(rawText(path, "PRAGMA user_version") == "2")
        #expect(rawText(path, "PRAGMA journal_mode") == "wal")
        _ = try SlackTaskStore(path: path)
    }

    @Test func addInsertsAPastedLinkAsATodoWithoutFacts() throws {
        let store = try SlackTaskStore(path: tempPath())
        #expect(try store.add(rootLink, now: now) == .added)
        let task = try #require(try store.tasks(includeArchived: false).first)
        #expect(task.status == .todo)
        #expect(!task.archived)
        #expect(task.tagged == "2026-11-15")
        #expect(task.permalink == rootLink.permalink)
        #expect(task.channelName == nil && task.snippet == nil && task.replies == nil && task.repliesAtTag == nil && task.lastReply == nil)
    }

    @Test func addingTwiceExistsAndAnArchivedOneIsRestored() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, now: now)
        #expect(try store.add(rootLink, now: now) == .exists)
        let id = try #require(try store.tasks(includeArchived: false).first).id
        try store.setArchived(true, for: id)
        #expect(try store.tasks(includeArchived: false).isEmpty)
        #expect(try store.add(rootLink, now: now) == .restored)
        #expect(try store.tasks(includeArchived: false).count == 1)
    }

    @Test func aReplyLinkIsKeyedToTheThreadRoot() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(replyLink, now: now)
        #expect(try store.tasks(includeArchived: false).first?.threadTS == "1794536057.965929")
    }

    @Test func setStatusChangesOnlyTheStatus() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, now: now)
        let before = try #require(try store.tasks(includeArchived: false).first)
        try store.setStatus(.blocked, for: before.id)
        var after = try #require(try store.tasks(includeArchived: false).first)
        #expect(after.status == .blocked)
        after.status = .todo
        #expect(after == before)
    }

    @Test func archivedRowsAreHiddenUnlessAsked() throws {
        let store = try SlackTaskStore(path: tempPath())
        _ = try store.add(rootLink, now: now)
        let id = try #require(try store.tasks(includeArchived: false).first).id
        try store.setArchived(true, for: id)
        #expect(try store.tasks(includeArchived: false).isEmpty)
        #expect(try store.tasks(includeArchived: true).count == 1)
    }

    @Test func decodesARowWrittenTheWaySyncWritesIt() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        raw(path, """
        INSERT INTO tasks (channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced)
        VALUES ('C07R08WFC81', '1794536057.965929', 'https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929',
                'agent-network-eng', 'Store internal_account_number', 12, 10, '2026-11-13T02:14:17Z', '2026-11-13', '2026-11-15T10:00:00Z')
        """)
        let task = try #require(try store.tasks(includeArchived: false).first)
        #expect(task.channelName == "agent-network-eng")
        #expect(task.replies == 12 && task.repliesAtTag == 10 && task.newReplies == 2)
        #expect(task.lastReply == ISO8601DateFormatter().date(from: "2026-11-13T02:14:17Z"))
    }

    @Test func statusAndSyncFactsSurviveEachOthersWrites() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        _ = try store.add(rootLink, now: now)
        let id = try #require(try store.tasks(includeArchived: false).first).id
        try store.setStatus(.inprogress, for: id)
        raw(path, "UPDATE tasks SET replies = 5, last_reply = '2026-11-14T01:00:00Z'")
        var task = try #require(try store.tasks(includeArchived: false).first)
        #expect(task.status == .inprogress && task.replies == 5)
        raw(path, "UPDATE tasks SET replies = 6")
        try store.setStatus(.done, for: id)
        task = try #require(try store.tasks(includeArchived: false).first)
        #expect(task.status == .done && task.replies == 6)
    }

    @Test func dataVersionChangesWhenAnotherConnectionWrites() throws {
        let path = tempPath()
        let store = try SlackTaskStore(path: path)
        let before = try store.dataVersion()
        raw(path, "INSERT INTO tasks (channel_id, thread_ts, permalink, tagged) VALUES ('C','1.1','p','2026-11-15')")
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

    @Test func upgradesAV1DatabaseInPlace() throws {
        let path = tempPath()
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        raw(path, """
        CREATE TABLE tasks (channel_id TEXT NOT NULL, thread_ts TEXT NOT NULL, permalink TEXT NOT NULL, channel_name TEXT, snippet TEXT,
          replies INTEGER, replies_at_tag INTEGER, last_reply TEXT, tagged TEXT NOT NULL, synced TEXT,
          status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
          archived INTEGER NOT NULL DEFAULT 0, PRIMARY KEY (channel_id, thread_ts));
        INSERT INTO tasks (channel_id, thread_ts, permalink, tagged, status) VALUES ('C', '1.1', 'p', '2026-11-15', 'blocked');
        PRAGMA user_version = 1;
        """)
        let store = try SlackTaskStore(path: path)
        let task = try #require(try store.tasks(includeArchived: false).first)
        #expect(task.status == .blocked)
        #expect(task.summary == nil && task.nextAction == nil && task.summaryReplies == nil)
        #expect(rawText(path, "PRAGMA user_version") == "2")
        raw(path, "UPDATE tasks SET summary = 'S', next_action = 'N', summary_replies = 3")
        let updated = try #require(try store.tasks(includeArchived: false).first)
        #expect(updated.summary == "S" && updated.nextAction == "N" && updated.summaryReplies == 3)
        _ = try SlackTaskStore(path: path)
    }
}
