import Foundation
import SQLite3
import Testing
@testable import StudioCore

@Suite struct FlowStoreTests {
    func tempPath() -> String { NSTemporaryDirectory() + "flows-\(UUID().uuidString)/nested/slack-tasks.db" }

    /// Plays the part of the MCP server: a second connection to the same file.
    func raw(_ path: String, _ sql: String) {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_busy_timeout(db, 5000)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    let graph = #"{"nodes":[{"id":"a","position":{"x":0,"y":0},"data":{"label":"A"},"type":"step"},{"id":"b","position":{"x":10,"y":20},"data":{"label":"B"}}],"edges":[{"id":"a-b","source":"a","target":"b"}]}"#

    func seeded() throws -> (FlowStore, String) {
        let path = tempPath()
        let store = try FlowStore(path: path)
        raw(path, """
        INSERT INTO flows (id, name, position, graph) VALUES (1, 'Happy path', 1, '\(graph)'), (2, 'Failure', 0, '{"nodes":[],"edges":[]}'), (3, 'Main', 2, '{"nodes":[],"edges":[]}');
        """)
        return (store, path)
    }

    @Test func anEmptyDatabaseHasNoFlows() throws {
        #expect(try FlowStore(path: tempPath()).list().isEmpty)
    }

    @Test func listIsFlatAndInPositionOrder() throws {
        let (store, _) = try seeded()
        #expect(try store.list().map(\.name) == ["Failure", "Happy path", "Main"])
        #expect(try store.list().map(\.id) == [2, 1, 3])
    }

    @Test func aFreshDatabaseHasNoProjectOrSectionTables() throws {
        let path = tempPath()
        _ = try FlowStore(path: path)
        #expect(tables(path).contains("flows"))
        #expect(!tables(path).contains("flow_projects"))
        #expect(!tables(path).contains("flow_sections"))
    }

    func tables(_ path: String) -> Set<String> {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type = 'table'", -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        var names = Set<String>()
        while sqlite3_step(statement) == SQLITE_ROW { names.insert(String(cString: sqlite3_column_text(statement, 0))) }
        return names
    }

    @Test func aDatabaseWithProjectsAndSectionsIsFlattenedKeepingIdsGraphsAndOrder() throws {
        let path = tempPath()
        try FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        raw(path, """
        CREATE TABLE flow_projects (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL UNIQUE, position INTEGER NOT NULL);
        CREATE TABLE flow_sections (id INTEGER PRIMARY KEY AUTOINCREMENT, project_id INTEGER NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL, UNIQUE (project_id, name));
        CREATE TABLE flows (id INTEGER PRIMARY KEY AUTOINCREMENT, section_id INTEGER NOT NULL, name TEXT NOT NULL, position INTEGER NOT NULL, graph TEXT NOT NULL DEFAULT '{"nodes":[],"edges":[]}', UNIQUE (section_id, name));
        INSERT INTO flow_projects (id, name, position) VALUES (1, 'Payments', 0), (2, 'Lending', 1);
        INSERT INTO flow_sections (id, project_id, name, position) VALUES (1, 1, 'Refund', 0), (2, 1, 'Top up', 1), (3, 2, 'Disbursal', 0);
        INSERT INTO flows (id, section_id, name, position, graph) VALUES (10, 1, 'Main', 0, '\(graph)'), (11, 2, 'Main', 0, '{"nodes":[],"edges":[]}'), (12, 3, 'Other', 0, '{"nodes":[],"edges":[]}'), (13, 1, 'Failure', 1, '{"nodes":[],"edges":[]}');
        """)
        let store = try FlowStore(path: path)
        let items = try store.list()
        #expect(items.map(\.id) == [10, 13, 11, 12])
        #expect(items.map(\.name) == ["Main", "Failure", "Main (Top up)", "Other"])
        #expect(try store.graph(id: 10) == graph)
        #expect(!tables(path).contains("flow_projects"))
        #expect(!tables(path).contains("flow_sections"))
        #expect(try FlowStore(path: path).list().count == 4)
    }

    @Test func graphReturnsTheStoredJSONOrNilForAnUnknownFlow() throws {
        let (store, _) = try seeded()
        #expect(try store.graph(id: 1) == graph)
        #expect(try store.graph(id: 99) == nil)
    }

    @Test func savingAGraphReplacesTheStoredOneVerbatim() throws {
        let (store, _) = try seeded()
        let edited = #"{"nodes":[{"id":"n1","position":{"x":1,"y":2},"data":{"label":"New"}}],"edges":[]}"#
        try store.saveGraph(edited, flow: 1)
        #expect(try store.graph(id: 1) == edited)
        #expect(try store.graph(id: 2) == #"{"nodes":[],"edges":[]}"#)
    }

    @Test func savingAGraphWithoutNodesAndEdgesArraysIsRefusedAndKeepsTheStoredOne() throws {
        let (store, _) = try seeded()
        for bad in ["not json", "[]", #"{"nodes":[]}"#, #"{"nodes":{},"edges":[]}"#] {
            #expect(throws: (any Error).self) { try store.saveGraph(bad, flow: 1) }
        }
        #expect(try store.graph(id: 1) == graph)
    }

    @Test func savingAGraphForAMissingFlowDoesNothing() throws {
        let (store, _) = try seeded()
        try store.saveGraph(#"{"nodes":[],"edges":[]}"#, flow: 99)
        #expect(try store.graph(id: 1) == graph)
        #expect(try store.graph(id: 99) == nil)
    }

    @Test func dataVersionChangesWhenTheMCPServerWritesAFlow() throws {
        let (store, path) = try seeded()
        let before = try store.dataVersion()
        raw(path, "UPDATE flows SET name = 'Renamed' WHERE id = 1")
        #expect(try store.dataVersion() != before)
    }

    @Test func creatingAFlowAppendsItWithAnEmptyGraphAndReturnsItsId() throws {
        let (store, _) = try seeded()
        let id = try store.create(name: "  Checkout  ")
        #expect(try store.list().last == FlowItem(id: id, name: "Checkout"))
        #expect(try store.graph(id: id) == #"{"nodes":[],"edges":[]}"#)
    }

    @Test func aBlankOrRepeatedNameIsRefusedWhenCreatingOrRenaming() throws {
        let (store, _) = try seeded()
        #expect(throws: (any Error).self) { try store.create(name: "   ") }
        #expect(throws: (any Error).self) { try store.create(name: "Main") }
        #expect(throws: (any Error).self) { try store.rename(1, to: "Main") }
        #expect(throws: (any Error).self) { try store.rename(1, to: "") }
        #expect(try store.list().map(\.name) == ["Failure", "Happy path", "Main"])
    }

    @Test func renamingKeepsIdGraphAndPosition() throws {
        let (store, _) = try seeded()
        try store.rename(1, to: "Success path")
        #expect(try store.list().map(\.name) == ["Failure", "Success path", "Main"])
        #expect(try store.graph(id: 1) == graph)
        try store.rename(1, to: "Success path")
    }

    @Test func deletingRemovesOnlyThatFlowAndAMissingOneDoesNothing() throws {
        let (store, _) = try seeded()
        try store.delete(1)
        #expect(try store.list().map(\.id) == [2, 3])
        #expect(try store.graph(id: 1) == nil)
        try store.delete(99)
        #expect(try store.list().count == 2)
    }
}
