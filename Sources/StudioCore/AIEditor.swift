import Foundation

public enum AIEditError: Error, Equatable {
    case failed(String), timedOut, emptyResponse
}

/// Edits a document from a plain-language instruction by running the Claude Code CLI in print mode.
public struct AIEditor {
    private let claude: URL
    private let model: String
    private let timeout: TimeInterval

    public init(claude: URL, model: String = "sonnet", timeout: TimeInterval = 120) {
        self.claude = claude
        self.model = model
        self.timeout = timeout
    }

    public static func systemPrompt(for kind: DocumentKind) -> String {
        switch kind {
        case .diagram:
            return """
            You edit PlantUML diagrams. You receive the current source inside <document> and a change request inside <instruction>.
            Reply with the complete updated PlantUML source and nothing else: no explanations, no commentary, no markdown fences.
            Keep @startuml and @enduml. Keep existing participants, names, order and styling unless the request changes them. Change as little as possible.
            Output valid PlantUML only. Never add remote !include lines or URLs.
            If the request is unclear or cannot be done, reply with the source unchanged.
            """
        case .markdown:
            return """
            You edit markdown documents. You receive the current document inside <document> and a change request inside <instruction>.
            Reply with the complete updated markdown document and nothing else: no explanations, no commentary, no markdown fences around the whole document.
            Keep the frontmatter, headings, wording and structure unless the request changes them. Change as little as possible.
            PlantUML diagrams are fenced blocks tagged plantuml; keep them valid, and write new diagrams as plantuml fenced blocks.
            Never add raw HTML, remote !include lines or URLs inside diagrams.
            If the request is unclear or cannot be done, reply with the document unchanged.
            """
        }
    }

    static func userMessage(document: String, instruction: String) -> String {
        "<document>\n\(document)\n</document>\n<instruction>\n\(instruction)\n</instruction>\n"
    }

    /// Strips a code fence the model wrapped around the whole reply, and normalizes the trailing newline.
    public static func cleaned(_ raw: String, kind: DocumentKind) -> String {
        var lines = raw.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        if lines.count >= 2, let first = lines.first, let last = lines.last,
           first.hasPrefix("```"), last.trimmingCharacters(in: .whitespaces) == "```" {
            let tag = first.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased()
            let wrappers: Set<String> = kind == .diagram ? ["", "plantuml", "puml", "uml"] : ["markdown", "md"]
            if wrappers.contains(tag) { lines = Array(lines.dropFirst().dropLast()) }
        }
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
    }

    public func edit(_ document: String, instruction: String, kind: DocumentKind) async throws -> String {
        let output = try await run(input: Self.userMessage(document: document, instruction: instruction), kind: kind)
        if output.timedOut { throw AIEditError.timedOut }
        if output.status != 0 {
            let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AIEditError.failed(message.isEmpty ? "claude exited with status \(output.status)" : message)
        }
        if output.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { throw AIEditError.emptyResponse }
        return Self.cleaned(output.stdout, kind: kind)
    }

    private struct Output { let status: Int32; let stdout: String; let stderr: String; let timedOut: Bool }

    private final class Flag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.lock(); value = true; lock.unlock() }
        var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    }

    private func run(input: String, kind: DocumentKind) async throws -> Output {
        let process = Process()
        process.executableURL = claude
        process.arguments = ["-p", "--system-prompt", Self.systemPrompt(for: kind), "--tools", "", "--setting-sources", "",
                             "--no-session-persistence", "--disable-slash-commands", "--model", model]
        var environment = ProcessInfo.processInfo.environment
        environment["CLAUDE_CODE_DISABLE_CLAUDE_MDS"] = "1"
        process.environment = environment
        process.currentDirectoryURL = FileManager.default.temporaryDirectory
        let stdin = Pipe(), stdout = Pipe(), stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let timeout = self.timeout
        return try await Task.detached {
            signal(SIGPIPE, SIG_IGN)
            try process.run()
            let timedOut = Flag()
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { timedOut.set(); process.terminate() }
            }
            DispatchQueue.global().async {
                try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8))
                try? stdin.fileHandleForWriting.close()
            }
            let errReader = Task.detached { stderr.fileHandleForReading.readDataToEndOfFile() }
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errData = await errReader.value
            process.waitUntilExit()
            return Output(status: process.terminationStatus,
                          stdout: String(decoding: outData, as: UTF8.self),
                          stderr: String(decoding: errData, as: UTF8.self),
                          timedOut: timedOut.isSet)
        }.value
    }
}
