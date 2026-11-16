import Foundation

public enum SlackSyncError: Error, Equatable {
    case failed(String), timedOut
}

/// Runs the sync-slack-tasks skill through the Claude Code CLI in print mode.
public struct SlackSync {
    private let claude: URL
    private let model: String
    private let timeout: TimeInterval

    public init(claude: URL, model: String = "sonnet", timeout: TimeInterval = 600) {
        self.claude = claude
        self.model = model
        self.timeout = timeout
    }

    public static func tagPrompt(_ tags: [SlackTag]) -> String {
        let list = tags.map { "`\($0.id)`" }.joined(separator: ", ")
        return "Use the sync-slack-tasks skill to sync only the \(tags.count == 1 ? "tag" : "tags") \(list). Do not sync any other tag. End with the one-line report from the skill."
    }

    public static func taskPrompt(number: Int) -> String {
        "Use the sync-slack-tasks skill, single task mode, to refresh only task #\(number). Do not sync any other thread. End with a one-line report."
    }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    /// Sends the prompt on stdin and returns the CLI's trimmed reply.
    public func run(_ prompt: String) async throws -> String {
        let process = Process()
        process.executableURL = claude
        process.arguments = ["-p", "--allowedTools", "mcp__workbench__*,mcp__sequence-vaults__*,Skill",
                             "--disallowedTools", "mcp__claude_ai_Slack__*", "--no-session-persistence", "--model", model]
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let timeout = self.timeout
        let output: (status: Int32, out: String, err: String, timedOut: Bool) = try await Task.detached {
            signal(SIGPIPE, SIG_IGN)
            try process.run()
            let timedOut = Flag()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timedOut.set(); process.terminate() }
            }
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(prompt.utf8))
                try? stdin.fileHandleForWriting.close()
            }
            let errReader = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = await errReader.value
            process.waitUntilExit()
            return (process.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self), timedOut.isSet)
        }.value
        if output.timedOut { throw SlackSyncError.timedOut }
        if output.status != 0 {
            let message = output.err.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SlackSyncError.failed(message.isEmpty ? "claude exited with status \(output.status)" : message)
        }
        return output.out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
