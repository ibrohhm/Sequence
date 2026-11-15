import Foundation
import SQLite3

public struct SlackStoreError: Error, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
}

/// The Slack tasks database shared with the sync tool in mcp/. Sequence writes only status and archived (and new pasted rows).
public final class SlackTaskStore {
    public static let ddl = """
    CREATE TABLE IF NOT EXISTS tasks (
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
      status TEXT NOT NULL DEFAULT 'todo' CHECK (status IN ('todo','inprogress','blocked','done')),
      archived INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY (channel_id, thread_ts)
    )
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
        try exec(Self.ddl)
        try upgrade()
    }

    deinit { sqlite3_close(db) }

    private func upgrade() throws {
        let version = try rows("PRAGMA user_version", []) { Int(sqlite3_column_int64($0, 0)) }.first ?? 0
        guard version < 2 else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            let have = Set(try rows("PRAGMA table_info(tasks)", []) { String(cString: sqlite3_column_text($0, 1)) })
            for (name, type) in [("summary", "TEXT"), ("next_action", "TEXT"), ("summary_replies", "INTEGER")] where !have.contains(name) {
                try exec("ALTER TABLE tasks ADD COLUMN \(name) \(type)")
            }
            try exec("PRAGMA user_version = 2")
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    public func tasks(includeArchived: Bool) throws -> [SlackTask] {
        let sql = """
        SELECT channel_id, thread_ts, permalink, channel_name, snippet, replies, replies_at_tag, last_reply, tagged, synced, status, archived,
               summary, next_action, summary_replies
        FROM tasks\(includeArchived ? "" : " WHERE archived = 0")
        """
        let formatter = ISO8601DateFormatter()
        return try rows(sql, []) { statement in
            func text(_ column: Int32) -> String? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_text(statement, column).map { String(cString: $0) }
            }
            func int(_ column: Int32) -> Int? {
                sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : Int(sqlite3_column_int64(statement, column))
            }
            return SlackTask(
                channelID: text(0) ?? "", threadTS: text(1) ?? "", permalink: text(2) ?? "", channelName: text(3), snippet: text(4),
                replies: int(5), repliesAtTag: int(6), lastReply: text(7).flatMap { formatter.date(from: $0) },
                tagged: text(8) ?? "", synced: text(9), status: SlackStatus(rawValue: text(10) ?? "") ?? .todo, archived: (int(11) ?? 0) != 0,
                summary: text(12), nextAction: text(13), summaryReplies: int(14)
            )
        }
    }

    public func setStatus(_ status: SlackStatus, for id: String) throws {
        let (channel, thread) = Self.split(id)
        try run("UPDATE tasks SET status = ? WHERE channel_id = ? AND thread_ts = ?", [.text(status.rawValue), .text(channel), .text(thread)])
    }

    public func setArchived(_ archived: Bool, for id: String) throws {
        let (channel, thread) = Self.split(id)
        try run("UPDATE tasks SET archived = ? WHERE channel_id = ? AND thread_ts = ?", [.int(archived ? 1 : 0), .text(channel), .text(thread)])
    }

    public func add(_ link: SlackLink, now: Date = Date()) throws -> AddResult {
        try exec("BEGIN IMMEDIATE")
        do {
            let existing = try rows("SELECT archived FROM tasks WHERE channel_id = ? AND thread_ts = ?",
                                    [.text(link.channelID), .text(link.rootTS)]) { Int(sqlite3_column_int64($0, 0)) }
            let result: AddResult
            if let archived = existing.first {
                if archived != 0 {
                    try run("UPDATE tasks SET archived = 0 WHERE channel_id = ? AND thread_ts = ?", [.text(link.channelID), .text(link.rootTS)])
                    result = .restored
                } else {
                    result = .exists
                }
            } else {
                let tagged = String(ISO8601DateFormatter().string(from: now).prefix(10))
                try run("INSERT INTO tasks (channel_id, thread_ts, permalink, tagged) VALUES (?, ?, ?, ?)",
                        [.text(link.channelID), .text(link.rootTS), .text(link.permalink), .text(tagged)])
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

    private static func split(_ id: String) -> (String, String) {
        guard let slash = id.firstIndex(of: "/") else { return (id, "") }
        return (String(id[..<slash]), String(id[id.index(after: slash)...]))
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
