import Testing
import Foundation
@testable import StudioCore

private func stubClaude(_ body: String) throws -> (exe: URL, dir: URL) {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let exe = dir.appendingPathComponent("claude")
    try "#!/bin/sh\n\(body)\n".write(to: exe, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: exe.path)
    return (exe, dir)
}

@Suite struct AIEditorTests {
    @Test func returnsTheStubsStdoutAsTheNewDocument() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; printf '@startuml\\nA -> B\\n@enduml\\n'")
        let result = try await AIEditor(claude: exe).edit("old", instruction: "x", kind: .diagram)
        #expect(result == "@startuml\nA -> B\n@enduml\n")
    }

    @Test func sendsDocumentAndInstructionOnStdinAndLocksDownTheCLI() async throws {
        let (exe, dir) = try stubClaude("cat > \"$(dirname \"$0\")/stdin.txt\"; for a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"$(dirname \"$0\")/args.txt\"; printf 'ok\\n'")
        _ = try await AIEditor(claude: exe).edit("MY DOCUMENT", instruction: "MY INSTRUCTION", kind: .diagram)
        let stdin = try String(contentsOf: dir.appendingPathComponent("stdin.txt"), encoding: .utf8)
        let args = try String(contentsOf: dir.appendingPathComponent("args.txt"), encoding: .utf8).components(separatedBy: "\n")
        #expect(stdin.contains("MY DOCUMENT") && stdin.contains("MY INSTRUCTION"))
        #expect(args.contains("-p") && args.contains("--no-session-persistence"))
        let toolsIndex = try #require(args.firstIndex(of: "--tools"))
        #expect(args[toolsIndex + 1] == "")
        let systemIndex = try #require(args.firstIndex(of: "--system-prompt"))
        #expect(args[systemIndex + 1] == AIEditor.systemPrompt(for: .diagram).components(separatedBy: "\n")[0])
    }

    @Test func nonZeroExitThrowsFailedWithStderr() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; echo 'not logged in' >&2; exit 1")
        await #expect(throws: AIEditError.failed("not logged in")) {
            try await AIEditor(claude: exe).edit("d", instruction: "i", kind: .diagram)
        }
    }

    @Test func emptyOutputThrowsEmptyResponse() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; printf '  \\n'")
        await #expect(throws: AIEditError.emptyResponse) {
            try await AIEditor(claude: exe).edit("d", instruction: "i", kind: .diagram)
        }
    }

    @Test func slowCLIIsStoppedAfterTheTimeout() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; sleep 5")
        await #expect(throws: AIEditError.timedOut) {
            try await AIEditor(claude: exe, timeout: 0.4).edit("d", instruction: "i", kind: .diagram)
        }
    }

    @Test func fencedDiagramReplyIsUnwrapped() {
        let raw = "```plantuml\n@startuml\nA -> B\n@enduml\n```\n"
        #expect(AIEditor.cleaned(raw, kind: .diagram) == "@startuml\nA -> B\n@enduml\n")
    }

    @Test func markdownDocumentThatEndsWithADiagramBlockIsLeftAlone() {
        let raw = "```plantuml\n@startuml\nA -> B\n@enduml\n```\n"
        #expect(AIEditor.cleaned(raw, kind: .markdown) == raw)
    }

    @Test func markdownWrappedInAMarkdownFenceIsUnwrapped() {
        let raw = "```markdown\n# Title\n\n```plantuml\nA -> B\n```\n```\n"
        #expect(AIEditor.cleaned(raw, kind: .markdown) == "# Title\n\n```plantuml\nA -> B\n```\n")
    }

    @Test func plainReplyGetsOneTrailingNewline() {
        #expect(AIEditor.cleaned("# Title\n\n\n", kind: .markdown) == "# Title\n")
    }

    @Test func systemPromptsDemandTheDocumentOnlyAndNameTheFormat() {
        let diagram = AIEditor.systemPrompt(for: .diagram)
        let markdown = AIEditor.systemPrompt(for: .markdown)
        #expect(diagram.contains("PlantUML") && diagram.contains("@startuml") && diagram.contains("no markdown fences"))
        #expect(markdown.contains("markdown") && markdown.contains("no markdown fences around the whole document"))
    }

    @Test func claudeIsFoundInASearchDir() throws {
        let (exe, dir) = try stubClaude("exit 0")
        #expect(try ToolLocator(searchDirs: [dir]).claude().path == exe.path)
    }

    @Test func missingClaudeThrowsClaudeMissing() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        #expect(throws: ToolError.claudeMissing) { try ToolLocator(searchDirs: [dir]).claude() }
    }
}
