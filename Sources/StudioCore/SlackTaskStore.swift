import Foundation
import SQLite3

public struct SlackStoreError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// The Slack tasks database shared with the sync tool in mcp/. Sequence writes tags, card status and archived flags, and new cards for pasted links.
public final class SlackTaskStore {
    public static let tagsDDL = """
    CREATE TABLE IF NOT EXISTS tags (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('board','list')),
      slack_list TEXT NOT NULL DEFAULT 'none' CHECK (slack_list IN ('none','todo','saved')),
      reactions TEXT NOT NULL DEFAULT '[]',
      columns TEXT NOT NULL DEFAULT '[]',
      position INTEGER NOT NULL,
      builtin INTEGER NOT NULL DEFAULT 0
    )
    """

    public static let tasksDDL = """
    CREATE TABLE IF NOT EXISTS tasks (
      tag TEXT NOT NULL,
      channel_id TEXT NOT NULL,
      thread_ts TEXT NOT NULL,
      permalink TEXT NOT NULL,
      channel_name TEXT,
      snippet TEXT,
      replies INTEGER,
      replies_at_tag INTEGER,
      last_reply TEXT,
      tagged TEXT NOT NULL,
      synced TEXT,
      summary TEXT,
      next_action TEXT,
      summary_replies INTEGER,
      status TEXT NOT NULL DEFAULT '',
      archived INTEGER NOT NULL DEFAULT 0,
      number INTEGER,
      PRIMARY KEY (tag, channel_id, thread_ts)
    )
    """

    public static let numberIndexDDL = """
    CREATE UNIQUE INDEX IF NOT EXISTS tasks_number ON tasks(number)
    """

    public enum AddResult { case added, restored, exists }

    private enum Bind { case text(String), int(Int) }
    private var db: OpaquePointer?

    public static func defaultPath() -> String {
        ProcessInfo.processInfo.environment["SEQUENCE_SLACK_DB"]
            ?? NSHomeDirectory() + "/Library/Application Support/Sequence/slack-tasks.db"
    }

    public init(path: String = SlackTaskStore.defaultPath()) throws {
        let folder = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw failure("Cannot open the Slack tasks database") }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode = WAL")
        try exec(Self.tagsDDL)
        try exec(Self.tasksDDL)
        try upgrade()
        try ensureNumbers()
    }

    deinit { sqlite3_close(db) }

    private static let copied = "channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced, summary, next_action, summary_replies, archived"

    /// Gives every card without a number the next one, oldest tagged first. Call inside a transaction.
    private func assignMissingNumbers() throws {
        let unnumbered = try rows("SELECT rowid FROM tasks WHERE number IS NULL ORDER BY tagged, rowid", []) { Int(sqlite3_column_int64($0, 0)) }
        var next = try rows("SELECT COALESCE(MAX(number), 0) FROM tasks", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        for id in unnumbered {
            next += 1
            try run("UPDATE tasks SET number = ? WHERE rowid = ?", [.int(next), .int(id)])
        }
    }

    /// Cards written by an older build or an older running server have no number; number them on every open.
    private func ensureNumbers() throws {
        let missing = try rows("SELECT 1 FROM tasks WHERE number IS NULL LIMIT 1", []) { _ in true }
        guard !missing.isEmpty else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            try assignMissingNumbers()
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    private func upgrade() throws {
        let version = try rows("PRAGMA user_version", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        guard version < 5 else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            let have = Set(try rows("PRAGMA table_info(tasks)", []) { String(cString: sqlite3_column_text($0, 1)) })
            if !have.contains("tag") {
                for (name, type) in [("summary", "TEXT"), ("next_action", "TEXT"), ("summary_replies", "INTEGER")] where !have.contains(name) {
                    try exec("ALTER TABLE tasks ADD COLUMN \(name) \(type)")
                }
                try exec(Self.tasksDDL.replacingOccurrences(of: "EXISTS tasks (", with: "EXISTS tasks_v3 ("))
                try exec("""
                INSERT INTO tasks_v3 (tag, \(Self.copied), status)
                SELECT 'todo', \(Self.copied),
                       CASE status WHEN 'todo' THEN 'Todo' WHEN 'inprogress' THEN 'In progress' WHEN 'blocked' THEN 'Blocked' WHEN 'done' THEN 'Done' ELSE status END
                FROM tasks
                """)
                try exec("DROP TABLE tasks")
                try exec("ALTER TABLE tasks_v3 RENAME TO tasks")
            } else if !have.contains("number") {
                try exec("ALTER TABLE tasks ADD COLUMN number INTEGER")
            }
            let tagCount = try rows("SELECT COUNT(*) FROM tags", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
            if tagCount == 0 {
                try exec("""
                INSERT INTO tags (id, name, kind, slack_list, reactions, columns, position, builtin) VALUES
                ('todo', 'To-do', 'board', 'todo', '["loading","loading1"]', '["Todo","In progress","Blocked","Done"]', 0, 1),
                ('saved', 'Saved', 'list', 'saved', '[]', '[]', 1, 1)
                """)
            }
            try assignMissingNumbers()
            try exec(Self.numberIndexDDL)
            let standard = Self.encodeList(SlackColumns.all)
            let boardTags = try rows("SELECT id FROM tags WHERE kind = 'board'", []) { String(cString: sqlite3_column_text($0, 0)) }
            for id in boardTags {
                try run("UPDATE tags SET columns = ? WHERE id = ?", [.text(standard), .text(id)])
                let cards = try rows("SELECT rowid, status FROM tasks WHERE tag = ?", [.text(id)]) { (Int(sqlite3_column_int64($0, 0)), String(cString: sqlite3_column_text($0, 1))) }
                for (rowid, status) in cards {
                    let next = SlackColumns.canonical(status) ?? SlackColumns.all[0]
                    if next != status { try run("UPDATE tasks SET status = ? WHERE rowid = ?", [.text(next), .int(rowid)]) }
                }
            }
            try exec("PRAGMA user_version = 5")
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: Tags

    public func tags() throws -> [SlackTag] {
        try rows("SELECT id, name, kind, slack_list, reactions, columns, position, builtin FROM tags ORDER BY position, id", []) { statement in
            func text(_ column: Int32) -> String { sqlite3_column_text(statement, column).map { String(cString: $0) } ?? "" }
            return SlackTag(id: text(0), name: text(1), kind: SlackTagKind(rawValue: text(2)) ?? .board, slackList: SlackList(rawValue: text(3)) ?? .none,
                            reactions: Self.decodeList(text(4)), columns: Self.decodeList(text(5)),
                            position: Int(sqlite3_column_int64(statement, 6)), builtin: sqlite3_column_int64(statement, 7) != 0)
        }
    }

    /// Adds or updates a tag. A board tag always has the standard columns; a built-in tag keeps its kind and Slack list;
    /// a new tag goes after the others.
    public func saveTag(_ tag: SlackTag) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            let existing = try tags().first { $0.id == tag.id }
            let kind = (existing?.builtin == true) ? existing!.kind : tag.kind
            if let message = SlackTagRules.validate(name: tag.name, reactions: tag.reactions) { throw SlackStoreError(message: message) }
            let reactions = Self.encodeList(tag.reactions)
            let columns = Self.encodeList(kind == .board ? SlackColumns.all : [])
            if existing != nil {
                try run("UPDATE tags SET name = ?, kind = ?, reactions = ?, columns = ? WHERE id = ?",
                        [.text(tag.name), .text(kind.rawValue), .text(reactions), .text(columns), .text(tag.id)])
            } else {
                let next = (try rows("SELECT COALESCE(MAX(position), -1) + 1 FROM tags", []) { Int(sqlite3_column_int64($0, 0)) }.first) ?? 0
                try run("INSERT INTO tags (id, name, kind, slack_list, reactions, columns, position, builtin) VALUES (?, ?, ?, 'none', ?, ?, ?, 0)",
                        [.text(tag.id), .text(tag.name), .text(kind.rawValue), .text(reactions), .text(columns), .int(next)])
            }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// Removes a custom tag. Its cards stay in the database and show again if a tag with the same id is saved.
    public func deleteTag(_ id: String) throws {
        guard let tag = try tags().first(where: { $0.id == id }) else { return }
        if tag.builtin { throw SlackStoreError(message: "\(tag.name) is built in and cannot be deleted.") }
        try run("DELETE FROM tags WHERE id = ?", [.text(id)])
    }

    public func moveTag(_ id: String, to position: Int) throws {
        var ids = try tags().map(\.id)
        guard let from = ids.firstIndex(of: id) else { return }
        ids.remove(at: from)
        ids.insert(id, at: min(max(position, 0), ids.count))
        try exec("BEGIN IMMEDIATE")
        do {
            for (index, tagID) in ids.enumerated() { try run("UPDATE tags SET position = ? WHERE id = ?", [.int(index), .text(tagID)]) }
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    // MARK: Cards

    public func tasks(tag: String, includeArchived: Bool) throws -> [SlackTask] {
        let sql = """
        SELECT tag, channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced, status, archived,
               summary, next_action, summary_replies, number
        FROM tasks WHERE tag = ?\(includeArchived ? "" : " AND archived = 0")
        """
        let formatter = ISO8601DateFormatter()
        return try rows(sql, [.text(tag)]) { statement in
            func text(_ column: Int32) -> String? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_text(statement, column).map { String(cString: $0) }
            }
            func int(_ column: Int32) -> Int? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
            }
            return SlackTask(
                tag: text(0) ?? "", channelID: text(1) ?? "", threadTS: text(2) ?? "", permalink: text(3) ?? "", channelName: text(4), snippet: text(5),
                replies: int(6), repliesAtTag: int(7), lastReply: text(8).flatMap { formatter.date(from: $0) },
                tagged: text(9) ?? "", synced: text(10), status: text(11) ?? "", archived: (int(12) ?? 0) != 0,
                summary: text(13), nextAction: text(14), summaryReplies: int(15), number: int(16)
            )
        }
    }

    /// The cards of several tags, one tag after another.
    public func tasks(tags: [String], includeArchived: Bool) throws -> [SlackTask] {
        try tags.flatMap { try tasks(tag: $0, includeArchived: includeArchived) }
    }

    public func setStatus(_ status: String, for id: String) throws {
        let (tag, channel, thread) = Self.split(id)
        try run("UPDATE tasks SET status = ? WHERE tag = ? AND channel_id = ? AND thread_ts = ?", [.text(status), .text(tag), .text(channel), .text(thread)])
    }

    public func setArchived(_ archived: Bool, for id: String) throws {
        let (tag, channel, thread) = Self.split(id)
        try run("UPDATE tasks SET archived = ? WHERE tag = ? AND channel_id = ? AND thread_ts = ?", [.int(archived ? 1 : 0), .text(tag), .text(channel), .text(thread)])
    }

    public func add(_ link: SlackLink, tag: String, now: Date = Date()) throws -> AddResult {
        try exec("BEGIN IMMEDIATE")
        do {
            guard let found = try tags().first(where: { $0.id == tag }) else { throw SlackStoreError(message: "Unknown tag \"\(tag)\".") }
            let existing = try rows("SELECT archived FROM tasks WHERE tag = ? AND channel_id = ? AND thread_ts = ?",
                                    [.text(tag), .text(link.channelID), .text(link.rootTS)]) { Int(sqlite3_column_int64($0, 0)) }
            let result: AddResult
            if let archived = existing.first {
                if archived != 0 {
                    try run("UPDATE tasks SET archived = 0 WHERE tag = ? AND channel_id = ? AND thread_ts = ?", [.text(tag), .text(link.channelID), .text(link.rootTS)])
                    result = .restored
                } else {
                    result = .exists
                }
            } else {
                let tagged = String(ISO8601DateFormatter().string(from: now).prefix(10))
                let status = found.kind == .list ? "" : SlackColumns.all[0]
                let number = try rows("SELECT COALESCE(MAX(number), 0) + 1 FROM tasks", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 1
                try run("INSERT INTO tasks (tag, channel_id, thread_ts, permalink, tagged, status, number) VALUES (?, ?, ?, ?, ?, ?, ?)",
                        [.text(tag), .text(link.channelID), .text(link.rootTS), .text(link.permalink), .text(tagged), .text(status), .int(number)])
                result = .added
            }
            try exec("COMMIT")
            return result
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func dataVersion() throws -> Int {
        try rows("PRAGMA data_version", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
    }

    // MARK: Plumbing

    private static func split(_ id: String) -> (String, String, String) {
        let parts = id.split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        return (parts.count > 0 ? parts[0] : "", parts.count > 1 ? parts[1] : "", parts.count > 2 ? parts[2] : "")
    }

    private static func decodeList(_ text: String) -> [String] {
        (try? JSONDecoder().decode([String].self, from: Data(text.utf8))) ?? []
    }

    private static func encodeList(_ list: [String]) -> String {
        (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
    }

    private func failure(_ prefix: String) -> SlackStoreError {
        SlackStoreError(message: "\(prefix): \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")")
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure("Database error") }
    }

    private func run(_ sql: String, _ binds: [Bind]) throws {
        _ = try rows(sql, binds) { _ in () }
    }

    private func rows<T>(_ sql: String, _ binds: [Bind], _ read: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure("Database error") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, bind) in binds.enumerated() {
            switch bind {
            case .text(let value): sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient)
            case .int(let value): sqlite3_bind_int64(statement, Int32(index + 1), Int64(value))
            }
        }
        var result: [T] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW: result.append(read(statement))
            case SQLITE_DONE: return result
            default: throw failure("Database error")
            }
        }
    }
}
