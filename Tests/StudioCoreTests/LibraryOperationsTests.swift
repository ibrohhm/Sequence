import Testing
import Foundation
@testable import StudioCore

private func tempFolder() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ops \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@Suite struct LibraryOperationsTests {
    @Test func createFileAppendsExtensionAndWritesStarter() throws {
        let folder = try tempFolder()
        let url = try LibraryOperations.createFile(named: "payment flow", in: folder)
        #expect(url.lastPathComponent == "payment flow.puml")
        #expect(try String(contentsOf: url, encoding: .utf8) == "@startuml\n@enduml\n")
    }

    @Test func createFileKeepsExistingDiagramExtension() throws {
        let url = try LibraryOperations.createFile(named: "x.wsd", in: try tempFolder())
        #expect(url.lastPathComponent == "x.wsd")
    }

    @Test func createFileRejectsExisting() throws {
        let folder = try tempFolder()
        _ = try LibraryOperations.createFile(named: "a", in: folder)
        #expect(throws: LibraryOperationError.alreadyExists) { try LibraryOperations.createFile(named: "a", in: folder) }
    }

    @Test func namesWithSlashOrEmptyAreInvalid() throws {
        let folder = try tempFolder()
        #expect(throws: LibraryOperationError.invalidName) { try LibraryOperations.createFile(named: "a/b", in: folder) }
        #expect(throws: LibraryOperationError.invalidName) { try LibraryOperations.createFolder(named: "  ", in: folder) }
    }

    @Test func createFolderMakesDirectory() throws {
        let url = try LibraryOperations.createFolder(named: "rfc", in: try tempFolder())
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue)
    }

    @Test func renameKeepsDirectory() throws {
        let folder = try tempFolder()
        let old = try LibraryOperations.createFile(named: "old", in: folder)
        let renamed = try LibraryOperations.rename(old, to: "new.puml")
        #expect(renamed.deletingLastPathComponent().path == folder.path)
        #expect(FileManager.default.fileExists(atPath: renamed.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
    }

    @Test func renameOntoExistingFails() throws {
        let folder = try tempFolder()
        let a = try LibraryOperations.createFile(named: "a", in: folder)
        _ = try LibraryOperations.createFile(named: "b", in: folder)
        #expect(throws: LibraryOperationError.alreadyExists) { try LibraryOperations.rename(a, to: "b.puml") }
    }

    @Test func deleteMovesItemOutOfFolder() throws {
        let folder = try tempFolder()
        let url = try LibraryOperations.createFile(named: "gone", in: folder)
        try LibraryOperations.delete(url)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

@Suite struct MarkdownCreateTests {
    @Test func createMarkdownFileKeepsMdExtensionAndWritesHeading() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("md \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = try LibraryOperations.createFile(named: "rfc.md", in: dir)
        #expect(url.lastPathComponent == "rfc.md")
        #expect(try String(contentsOf: url, encoding: .utf8).hasPrefix("# "))
    }
}
