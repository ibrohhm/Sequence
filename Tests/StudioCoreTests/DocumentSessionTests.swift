import Testing
import Foundation
@testable import StudioCore

private func tempFile(_ content: String, name: String = "doc.puml") throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("doc \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent(name)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@MainActor @Suite struct DocumentSessionTests {
    @Test func editingMarksDirtySaveClears() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        #expect(!session.isDirty)
        session.text = "b"
        #expect(session.isDirty)
        try session.save()
        #expect(!session.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "b")
    }

    @Test func revertingTextToSavedContentIsNotDirty() throws {
        let session = try DocumentSession(url: try tempFile("a"))
        session.text = "ab"; session.text = "a"
        #expect(!session.isDirty)
    }

    @Test func saveWritesUTF8Unicode() throws {
        let url = try tempFile("x")
        let session = try DocumentSession(url: url)
        session.text = "participant \"Pembayaran 💳 é\""
        try session.save()
        #expect(try String(contentsOf: url, encoding: .utf8) == "participant \"Pembayaran 💳 é\"")
    }

    @Test func ownSaveIsNotReportedAsExternalChange() throws {
        let session = try DocumentSession(url: try tempFile("a"))
        session.text = "b"; try session.save()
        #expect(session.diskDidChange() == .none)
    }

    @Test func externalChangeOnCleanDocReloads() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        try "changed".write(to: url, atomically: true, encoding: .utf8)
        #expect(session.diskDidChange() == .reloaded)
        #expect(session.text == "changed")
        #expect(!session.isDirty)
    }

    @Test func externalChangeOnDirtyDocReportsConflictAndKeepsText() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        session.text = "mine"
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        #expect(session.diskDidChange() == .conflict)
        #expect(session.text == "mine")
    }

    @Test func keepMineSilencesSameConflictAndStaysDirty() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        session.text = "mine"
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        _ = session.diskDidChange()
        session.keepMine()
        #expect(session.diskDidChange() == .none)
        #expect(session.isDirty)
        #expect(session.text == "mine")
    }

    @Test func reloadFromDiskDiscardsEdits() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        session.text = "mine"
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        try session.reloadFromDisk()
        #expect(session.text == "theirs")
        #expect(!session.isDirty)
    }

    @Test func deletedFileReportsFileMissingAndKeepsText() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        session.text = "unsaved"
        try FileManager.default.removeItem(at: url)
        #expect(session.diskDidChange() == .fileMissing)
        #expect(session.text == "unsaved")
    }

    @Test func pathWithSpaces() throws {
        let session = try DocumentSession(url: try tempFile("hi", name: "my doc.puml"))
        #expect(session.text == "hi")
    }

    @Test func relocateKeepsUnsavedEditsAndSavesToNewPath() throws {
        let url = try tempFile("a")
        let session = try DocumentSession(url: url)
        session.text = "edited"
        let moved = url.deletingLastPathComponent().appendingPathComponent("renamed.puml")
        try FileManager.default.moveItem(at: url, to: moved)
        session.relocate(to: moved)
        #expect(session.url == moved)
        #expect(session.isDirty)
        try session.save()
        #expect(try String(contentsOf: moved, encoding: .utf8) == "edited")
    }
}
