import Foundation

public enum ToolError: Error, Equatable { case javaMissing, dotMissing, claudeMissing }

/// Finds Java and Graphviz `dot` on a Finder-launched app's limited PATH.
public struct ToolLocator {
    public static let defaultDirs: [URL] = ["/opt/homebrew/opt/openjdk/bin", "/usr/local/opt/openjdk/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { URL(fileURLWithPath: $0) }

    /// Where the Claude Code CLI is usually installed.
    public static var claudeDirs: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [home.appendingPathComponent(".local/bin"), home.appendingPathComponent(".claude/local"), home.appendingPathComponent(".npm-global/bin"),
                URL(fileURLWithPath: "/opt/homebrew/bin"), URL(fileURLWithPath: "/usr/local/bin")]
    }

    /// The `bin` directory of the Java runtime bundled in the app's resources, if any.
    public static func bundledDirs(in resources: URL?) -> [URL] {
        resources.map { [$0.appendingPathComponent("jre/bin")] } ?? []
    }

    private let searchDirs: [URL]
    private let overrides: [String: URL]
    private let versionCheckTimeout: TimeInterval

    public init(searchDirs: [URL] = ToolLocator.defaultDirs, overrides: [String: URL] = [:], versionCheckTimeout: TimeInterval = 10) {
        self.searchDirs = searchDirs
        self.overrides = overrides
        self.versionCheckTimeout = versionCheckTimeout
    }

    public func java() throws -> URL {
        guard let url = find("java", verify: { Self.runsVersionCheck($0, timeout: versionCheckTimeout) }) else { throw ToolError.javaMissing }
        return url
    }

    public func dot() throws -> URL {
        guard let url = find("dot", verify: { _ in true }) else { throw ToolError.dotMissing }
        return url
    }

    public func claude() throws -> URL {
        guard let url = find("claude", verify: { _ in true }) else { throw ToolError.claudeMissing }
        return url
    }

    private func find(_ name: String, verify: (URL) -> Bool) -> URL? {
        let candidates = (overrides[name].map { [$0] } ?? []) + searchDirs.map { $0.appendingPathComponent(name) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) && verify($0) }
    }

    /// Runs `java -version` and waits for it without servicing the caller's run loop (`waitUntilExit` does, which let
    /// other main-thread events run while SwiftUI was creating the app model). A runtime that hangs counts as missing.
    private static func runsVersionCheck(_ url: URL, timeout: TimeInterval) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do { try process.run() } catch { return false }
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }
}
