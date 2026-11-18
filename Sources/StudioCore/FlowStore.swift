import Foundation
import SQLite3

public struct FlowItem: Equatable, Identifiable, Sendable {
    public let id: Int
    public let name: String
}

/// The flows table of the shared database: flows written by the MCP server; Sequence reads them and saves the graph its editor produces.
public final class FlowStore {
    public static let flowsDDL = """
    CREATE TABLE IF NOT EXISTS flows (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      position INTEGER NOT NULL,
      graph TEXT NOT NULL DEFAULT '{"nodes":[],"edges":[]}'
    )
    """

    private var db: OpaquePointer?

    public init(path: String = SlackTaskStore.defaultPath()) throws {
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        guard sqlite3_open(path, &db) == SQLITE_OK else { throw failure("Cannot open the flows database") }
        sqlite3_busy_timeout(db, 5000)
        try exec("PRAGMA journal_mode = WAL")
        try flatten()
        try exec(Self.flowsDDL)
    }

    deinit { sqlite3_close(db) }

    /// A database from the version that had projects and sections is flattened once: flows keep their ids and graphs, in project, section, flow order;
    /// a repeated name gets its section in brackets.
    private func flatten() throws {
        let columns = Set(try rows("PRAGMA table_info(flows)", []) { Self.text($0, 1) })
        guard columns.contains("section_id") else { return }
        try exec("BEGIN IMMEDIATE")
        do {
            let old = try rows("""
            SELECT f.id, f.name, COALESCE(s.name, ''), f.graph FROM flows f
            LEFT JOIN flow_sections s ON s.id = f.section_id LEFT JOIN flow_projects p ON p.id = s.project_id
            ORDER BY p.position, s.position, f.position, f.id
            """, []) { (Self.int($0, 0), Self.text($0, 1), Self.text($0, 2), Self.text($0, 3)) }
            try exec(Self.flowsDDL.replacingOccurrences(of: "EXISTS flows (", with: "EXISTS flows_flat ("))
            var used = Set<String>()
            for (index, flow) in old.enumerated() {
                var name = flow.1
                if used.contains(name) { name = "\(flow.1) (\(flow.2))" }
                var count = 2
                while used.contains(name) { name = "\(flow.1) (\(flow.2)) \(count)"; count += 1 }
                used.insert(name)
                try run("INSERT INTO flows_flat (id, name, position, graph) VALUES (?, ?, ?, ?)", [flow.0, name, index, flow.3])
            }
            try exec("DROP TABLE flows")
            try exec("DROP TABLE IF EXISTS flow_sections")
            try exec("DROP TABLE IF EXISTS flow_projects")
            try exec("ALTER TABLE flows_flat RENAME TO flows")
            try exec("COMMIT")
        } catch {
            try? exec("ROLLBACK")
            throw error
        }
    }

    /// The flows in position order.
    public func list() throws -> [FlowItem] {
        try rows("SELECT id, name FROM flows ORDER BY position, id", []) { FlowItem(id: Self.int($0, 0), name: Self.text($0, 1)) }
    }

    /// Adds an empty flow after the others and returns its id; the name is trimmed and must be new.
    @discardableResult
    public func create(name: String) throws -> Int {
        let clean = try validName(name, excluding: nil)
        try run("INSERT INTO flows (name, position) VALUES (?, (SELECT COALESCE(MAX(position), -1) + 1 FROM flows))", [clean])
        return Int(sqlite3_last_insert_rowid(db))
    }

    public func rename(_ id: Int, to name: String) throws {
        let clean = try validName(name, excluding: id)
        try run("UPDATE flows SET name = ? WHERE id = ?", [clean, id])
    }

    public func delete(_ id: Int) throws {
        try run("DELETE FROM flows WHERE id = ?", [id])
    }

    private func validName(_ name: String, excluding id: Int?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if clean.isEmpty { throw SlackStoreError(message: "A flow needs a name.") }
        let taken = try rows("SELECT id FROM flows WHERE name = ?", [clean]) { Self.int($0, 0) }
        if taken.contains(where: { $0 != id }) { throw SlackStoreError(message: "A flow named \"\(clean)\" already exists.") }
        return clean
    }

    /// The React Flow JSON (`{"nodes":[...],"edges":[...]}`) of one flow.
    public func graph(id: Int) throws -> String? {
        try rows("SELECT graph FROM flows WHERE id = ?", [id]) { Self.text($0, 0) }.first
    }

    /// Replaces the stored graph of a flow with the editor's JSON, kept verbatim; it must hold `nodes` and `edges` arrays.
    public func saveGraph(_ graph: String, flow id: Int) throws {
        guard let object = (try? JSONSerialization.jsonObject(with: Data(graph.utf8))) as? [String: Any],
              object["nodes"] is [Any], object["edges"] is [Any] else {
            throw SlackStoreError(message: "The flow graph must be a JSON object with nodes and edges arrays")
        }
        try run("UPDATE flows SET graph = ? WHERE id = ?", [graph, id])
    }

    public func dataVersion() throws -> Int {
        try rows("PRAGMA data_version", []) { Self.int($0, 0) }.first ?? 0
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        sqlite3_column_text(statement, column).map { String(cString: $0) } ?? ""
    }

    private static func int(_ statement: OpaquePointer, _ column: Int32) -> Int { Int(sqlite3_column_int64(statement, column)) }

    private func failure(_ prefix: String) -> SlackStoreError {
        SlackStoreError(message: "\(prefix): \(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")")
    }

    private func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw failure("Database error") }
    }

    private func run(_ sql: String, _ binds: [Any]) throws {
        _ = try rows(sql, binds) { _ in () }
    }

    private func rows<T>(_ sql: String, _ binds: [Any], _ read: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure("Database error") }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (index, bind) in binds.enumerated() {
            if let value = bind as? Int { sqlite3_bind_int64(statement, Int32(index + 1), Int64(value)) }
            else if let value = bind as? String { sqlite3_bind_text(statement, Int32(index + 1), value, -1, transient) }
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
