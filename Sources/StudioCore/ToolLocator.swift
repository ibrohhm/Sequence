import Foundation

public enum ToolError: Error, Equatable { case javaMissing, dotMissing }

/// Finds Java and Graphviz `dot` on a Finder-launched app's limited PATH.
public struct ToolLocator {
    public static let defaultDirs: [URL] = ["/opt/homebrew/opt/openjdk/bin", "/usr/local/opt/openjdk/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin"].map { URL(fileURLWithPath: $0) }

    private let searchDirs: [URL]
    private let overrides: [String: URL]

    public init(searchDirs: [URL] = ToolLocator.defaultDirs, overrides: [String: URL] = [:]) {
        self.searchDirs = searchDirs
        self.overrides = overrides
    }

    public func java() throws -> URL {
        guard let url = find("java", verify: Self.runsVersionCheck) else { throw ToolError.javaMissing }
        return url
    }

    public func dot() throws -> URL {
        guard let url = find("dot", verify: { _ in true }) else { throw ToolError.dotMissing }
        return url
    }

    private func find(_ name: String, verify: (URL) -> Bool) -> URL? {
        let candidates = (overrides[name].map { [$0] } ?? []) + searchDirs.map { $0.appendingPathComponent(name) }
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0.path) && verify($0) }
    }

    private static func runsVersionCheck(_ url: URL) -> Bool {
        let process = Process()
        process.executableURL = url
        process.arguments = ["-version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
