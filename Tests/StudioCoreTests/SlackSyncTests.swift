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

private func tag(_ id: String, _ name: String) -> SlackTag {
    SlackTag(id: id, name: name, kind: .board, slackList: .none, reactions: [], columns: SlackColumns.all, position: 0, builtin: false)
}

@Suite struct SlackSyncTests {
    @Test func tagPromptNamesEveryTagByIdAndAsksForTheSkill() {
        let prompt = SlackSync.tagPrompt([tag("todo", "To-do"), tag("ticket-oncall", "Ticket Oncall")])
        #expect(prompt.contains("sync-slack-tasks"))
        #expect(prompt.contains("`todo`") && prompt.contains("`ticket-oncall`"))
        #expect(prompt.contains("only"))
    }

    @Test func taskPromptNamesTheNumberAndLimitsTheSyncToThatCard() {
        let prompt = SlackSync.taskPrompt(number: 12)
        #expect(prompt.contains("sync-slack-tasks") && prompt.contains("#12"))
        #expect(prompt.contains("only"))
    }

    @Test func slackConnectorIsDeniedAndOnlyTheSyncToolsAreAllowed() async throws {
        let (exe, dir) = try stubClaude("cat > \"$(dirname \"$0\")/stdin.txt\"; for a in \"$@\"; do printf '%s\\n' \"$a\"; done > \"$(dirname \"$0\")/args.txt\"; printf 'done\\n'")
        let output = try await SlackSync(claude: exe).run("MY PROMPT")
        let stdin = try String(contentsOf: dir.appendingPathComponent("stdin.txt"), encoding: .utf8)
        let args = try String(contentsOf: dir.appendingPathComponent("args.txt"), encoding: .utf8).components(separatedBy: "\n")
        #expect(output == "done")
        #expect(stdin == "MY PROMPT")
        #expect(args.contains("-p") && args.contains("--no-session-persistence"))
        let allowed = try #require(args.firstIndex(of: "--allowedTools"))
        #expect(args[allowed + 1].contains("mcp__workbench__*") && args[allowed + 1].contains("mcp__sequence-vaults__*") && args[allowed + 1].contains("Skill"))
        let denied = try #require(args.firstIndex(of: "--disallowedTools"))
        #expect(args[denied + 1].contains("mcp__claude_ai_Slack__*"))
    }

    @Test func nonZeroExitThrowsFailedWithStderr() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; echo 'not logged in' >&2; exit 1")
        await #expect(throws: SlackSyncError.failed("not logged in")) { try await SlackSync(claude: exe).run("p") }
    }

    @Test func slowCLIIsStoppedAfterTheTimeout() async throws {
        let (exe, _) = try stubClaude("cat >/dev/null; sleep 5")
        await #expect(throws: SlackSyncError.timedOut) { try await SlackSync(claude: exe, timeout: 0.3).run("p") }
    }
}
