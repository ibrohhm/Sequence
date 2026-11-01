import Testing
import Foundation
@testable import StudioCore

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("pg \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

@Suite struct PlaygroundTests {
    @Test func diagramStarterIsRenderablePlantUML() {
        let text = Playground.starter(.diagram)
        #expect(text.contains("@startuml") && text.contains("@enduml"))
    }

    @Test func markdownStarterShowsAnEmbeddedDiagram() {
        #expect(Playground.starter(.markdown).contains("```plantuml"))
    }

    @Test func eachKindHasItsOwnFileWithTheRightExtension() throws {
        let dir = try tempDir()
        let diagram = Playground.fileURL(for: .diagram, in: dir), markdown = Playground.fileURL(for: .markdown, in: dir)
        #expect(diagram != markdown)
        #expect(DocumentKind(url: diagram) == .diagram)
        #expect(DocumentKind(url: markdown) == .markdown)
    }

    @Test func ensureFileCreatesTheStarterWhenMissing() throws {
        let dir = try tempDir().appendingPathComponent("nested/Playground")
        let url = try Playground.ensureFile(for: .diagram, in: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == Playground.starter(.diagram))
    }

    @Test func ensureFileKeepsWhatWasAlreadyWritten() throws {
        let dir = try tempDir()
        let url = try Playground.ensureFile(for: .diagram, in: dir)
        try "my own diagram".write(to: url, atomically: true, encoding: .utf8)
        _ = try Playground.ensureFile(for: .diagram, in: dir)
        #expect(try String(contentsOf: url, encoding: .utf8) == "my own diagram")
    }

    @Test func containsTellsPlaygroundFilesFromLibraryFiles() throws {
        let dir = try tempDir()
        let inside = try Playground.ensureFile(for: .markdown, in: dir)
        #expect(Playground.contains(inside, in: dir))
        #expect(!Playground.contains(dir.deletingLastPathComponent().appendingPathComponent("other.puml"), in: dir))
    }
}
