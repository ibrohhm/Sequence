import Foundation

public enum RenderResult: Equatable {
    case svg(Data), failure(String), superseded
}

private let delimiter = "<<<PLANTUML-STUDIO-END>>>"

private func jvmArguments(jar: URL, extra: [String]) -> [String] {
    // Dead proxy with no bypass list: any URL fetch fails locally instead of reaching the network.
    ["-Djava.awt.headless=true", "-Dhttp.proxyHost=127.0.0.1", "-Dhttp.proxyPort=1",
     "-Dhttps.proxyHost=127.0.0.1", "-Dhttps.proxyPort=1", "-Dhttp.nonProxyHosts=",
     "-Dftp.proxyHost=127.0.0.1", "-Dftp.proxyPort=1", "-DsocksProxyHost=127.0.0.1", "-DsocksProxyPort=1",
     "-jar", jar.path] + extra
}

private func environment(dot: URL?) -> [String: String] {
    var env = ProcessInfo.processInfo.environment
    env["PLANTUML_SECURITY_PROFILE"] = "LEGACY"
    if let dot { env["GRAPHVIZ_DOT"] = dot.path }
    return env
}

private enum Analysis { case blocks(Int), rejected(String) }

/// Mirrors how PlantUML's pipe mode reads input: a `@start` line opens a block (resetting any open one), an `@end` line closes it.
private func analyze(_ source: String) -> Analysis {
    let remote = #"(?im)^\s*!includeurl\b|^\s*!(include|includesub|include_many|include_once|import|theme)\b[^\n]*https?://|%load_\w+\s*\(\s*["']?\s*https?://|<img:\s*https?://"#
    if source.range(of: remote, options: .regularExpression) != nil {
        return .rejected("Remote includes are blocked. Download the file and use a relative !include.")
    }
    var open = false
    var closed = 0
    for line in source.components(separatedBy: "\n") {
        let trimmed = line.drop(while: { $0 == " " || $0 == "\t" })
        if trimmed.hasPrefix("@start") { open = true }
        else if trimmed.hasPrefix("@end"), open { open = false; closed += 1 }
    }
    if closed == 0 && !open { return .rejected("Diagram needs a @startuml line and a closing @enduml.") }
    if open { return .rejected("Missing @enduml: the last @startuml block is not closed.") }
    return .blocks(closed)
}

private func errorMessage(fromSVG svg: String) -> String? {
    if svg.contains("Welcome to PlantUML") {
        return "PlantUML could not render this. Check for a missing !include file or an empty diagram."
    }
    let markers = ["Syntax Error", "[From string (line", "Cannot open", "Cannot include", "Some diagram description contains errors"]
    guard markers.contains(where: svg.contains) else { return nil }
    let regex = try! NSRegularExpression(pattern: "<text[^>]*>(.*?)</text>", options: [.dotMatchesLineSeparators])
    let range = NSRange(svg.startIndex..., in: svg)
    let lines = regex.matches(in: svg, range: range).compactMap { m -> String? in
        Range(m.range(at: 1), in: svg).map { String(svg[$0]) }
    }
    .map { $0.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">").replacingOccurrences(of: "&amp;", with: "&").replacingOccurrences(of: "&quot;", with: "\"") }
    .filter { !$0.isEmpty }
    return lines.isEmpty ? "Syntax error" : lines.joined(separator: "\n")
}

private final class WatchdogFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var fired = false
    func set() { lock.lock(); fired = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return fired }
}

private final class PipeSession: @unchecked Sendable {
    let baseDirectory: URL
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()

    init(java: URL, jar: URL, dot: URL?, baseDirectory: URL) throws {
        self.baseDirectory = baseDirectory
        process.executableURL = java
        process.arguments = jvmArguments(jar: jar, extra: ["-pipe", "-tsvg", "-charset", "UTF-8", "-pipedelimitor", delimiter])
        process.currentDirectoryURL = baseDirectory
        process.environment = environment(dot: dot)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    var isRunning: Bool { process.isRunning }

    /// Sends one source and blocks until `count` delimited diagrams are read; returns the first, nil if the process died.
    func roundTrip(_ source: String, count: Int) -> Data? {
        guard let bytes = (source + "\n").data(using: .utf8) else { return nil }
        do { try input.fileHandleForWriting.write(contentsOf: bytes) } catch { return nil }
        var first: Data?
        var seen = 0
        let marker = Data((delimiter).utf8)
        while seen < count {
            if let range = buffer.range(of: marker) {
                if first == nil { first = buffer.subdata(in: buffer.startIndex..<range.lowerBound) }
                var end = range.upperBound
                if end < buffer.endIndex, buffer[end] == 0x0A { end += 1 }
                buffer.removeSubrange(buffer.startIndex..<end)
                seen += 1
                continue
            }
            let chunk = output.fileHandleForReading.availableData
            if chunk.isEmpty { return nil }
            buffer.append(chunk)
        }
        return first
    }

    func stop() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}

/// Renders PlantUML source to SVG through one long-lived `-pipe` Java process.
public actor PlantUMLRenderer {
    private let javaURL: URL
    private let jarURL: URL
    private let dotURL: URL?
    private let timeout: Duration
    private var session: PipeSession?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(javaURL: URL, jarURL: URL, dotURL: URL?, timeout: Duration = .seconds(20)) {
        signal(SIGPIPE, SIG_IGN)
        self.timeout = timeout
        self.javaURL = javaURL
        self.jarURL = jarURL
        self.dotURL = dotURL
    }

    public func render(_ source: String, baseDirectory: URL) async -> RenderResult {
        if Task.isCancelled { return .superseded }
        let count: Int
        switch analyze(source) {
        case .rejected(let message): return .failure(message)
        case .blocks(let n): count = n
        }
        await acquire()
        defer { release() }
        if Task.isCancelled { return .superseded }
        let live: PipeSession
        do { live = try currentSession(for: baseDirectory) } catch { return .failure("Could not start Java: \(error.localizedDescription)") }
        let timeout = self.timeout
        let fired = WatchdogFlag()
        let watchdog = Task { try await Task.sleep(for: timeout); fired.set(); live.stop() }
        let data: Data? = await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { continuation.resume(returning: live.roundTrip(source, count: count)) }
        }
        let timedOut = fired.value
        watchdog.cancel()
        guard let data else {
            dropSession(ifCurrent: live)
            if Task.isCancelled { return .superseded }
            return .failure(timedOut ? "PlantUML took too long to render this diagram and was stopped." : "The PlantUML process stopped unexpectedly.")
        }
        if Task.isCancelled { return .superseded }
        let svg = String(decoding: data, as: UTF8.self)
        if let message = errorMessage(fromSVG: svg) { return .failure(message) }
        return .svg(data)
    }

    public func shutdown() { dropSession(ifCurrent: session) }

    private func acquire() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }

    private func release() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    private func currentSession(for baseDirectory: URL) throws -> PipeSession {
        if let session, session.isRunning, session.baseDirectory == baseDirectory { return session }
        session?.stop()
        let fresh = try PipeSession(java: javaURL, jar: jarURL, dot: dotURL, baseDirectory: baseDirectory)
        session = fresh
        return fresh
    }

    private func dropSession(ifCurrent target: PipeSession?) {
        guard let target, session === target else { return }
        target.stop()
        session = nil
    }
}

/// Renders PlantUML source to PNG with a one-shot run, using the same include restrictions as the live renderer.
public func exportPNG(source: String, baseDirectory: URL, javaURL: URL, jarURL: URL, dotURL: URL?) async -> Data? {
    guard case .blocks = analyze(source) else { return nil }
    return await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            let input = Pipe(), output = Pipe()
            process.executableURL = javaURL
            process.arguments = jvmArguments(jar: jarURL, extra: ["-pipe", "-tpng", "-charset", "UTF-8"])
            process.currentDirectoryURL = baseDirectory
            process.environment = environment(dot: dotURL)
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            do { try process.run() } catch { continuation.resume(returning: nil); return }
            input.fileHandleForWriting.write(Data(source.utf8))
            try? input.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            continuation.resume(returning: data.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]) ? data : nil)
        }
    }
}
