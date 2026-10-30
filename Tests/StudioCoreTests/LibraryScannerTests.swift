import Testing
import Foundation
@testable import StudioCore

private func tempRoot() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("lib \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func touch(_ root: URL, _ path: String) throws {
    let url = root.appendingPathComponent(path)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try "x".write(to: url, atomically: true, encoding: .utf8)
}

@Suite struct LibraryScannerTests {
    @Test func scanIncludesOnlyDiagramExtensions() throws {
        let root = try tempRoot()
        try touch(root, "a.puml"); try touch(root, "b.wsd"); try touch(root, "c.txt")
        #expect(try LibraryScanner.scan(root).map(\.name) == ["a.puml", "b.wsd"])
    }

    @Test func scanOmitsFoldersWithNoDiagrams() throws {
        let root = try tempRoot()
        try touch(root, "docs/readme.md"); try touch(root, "flows/pay.puml")
        #expect(try LibraryScanner.scan(root).map(\.name) == ["flows"])
    }

    @Test func scanKeepsNestedFoldersThatContainDiagrams() throws {
        let root = try tempRoot()
        try touch(root, "a/b/c/deep.pu")
        let tree = try LibraryScanner.scan(root)
        let deep = tree[0].children?[0].children?[0].children?[0]
        #expect(deep?.name == "deep.pu")
        #expect(deep?.isDirectory == false)
    }

    @Test func scanOrdersFoldersFirstThenCaseInsensitive() throws {
        let root = try tempRoot()
        try touch(root, "b.puml"); try touch(root, "A.puml"); try touch(root, "zeta/x.puml"); try touch(root, "Alpha/x.puml")
        #expect(try LibraryScanner.scan(root).map(\.name) == ["Alpha", "zeta", "A.puml", "b.puml"])
    }

    @Test func scanHandlesPathWithSpacesAndSkipsHiddenFolders() throws {
        let root = try tempRoot()
        try touch(root, "my flows/pay ment.puml"); try touch(root, ".git/hidden.puml")
        let tree = try LibraryScanner.scan(root)
        #expect(tree.map(\.name) == ["my flows"])
        #expect(tree[0].children?.map(\.name) == ["pay ment.puml"])
    }

    @Test func scanOfEmptyFolderIsEmpty() throws {
        #expect(try LibraryScanner.scan(try tempRoot()).isEmpty)
    }
}
