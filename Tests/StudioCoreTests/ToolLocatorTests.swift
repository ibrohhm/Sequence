import Testing
import Foundation
@testable import StudioCore

private func makeDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

@discardableResult
private func makeExecutable(_ name: String, in dir: URL, exitCode: Int32) throws -> URL {
    let url = dir.appendingPathComponent(name)
    try "#!/bin/sh\nexit \(exitCode)\n".write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Suite struct ToolLocatorTests {
    @Test func findsJavaInSearchDir() throws {
        let dir = try makeDir()
        let java = try makeExecutable("java", in: dir, exitCode: 0)
        let locator = ToolLocator(searchDirs: [dir])
        #expect(try locator.java().path == java.path)
    }

    @Test func overrideWinsOverSearchDirs() throws {
        let searchDir = try makeDir()
        let overrideDir = try makeDir()
        try makeExecutable("java", in: searchDir, exitCode: 0)
        let override = try makeExecutable("java", in: overrideDir, exitCode: 0)
        let locator = ToolLocator(searchDirs: [searchDir], overrides: ["java": override])
        #expect(try locator.java().path == override.path)
    }

    @Test func stubJavaThatFailsVersionCheckIsMissing() throws {
        let dir = try makeDir()
        try makeExecutable("java", in: dir, exitCode: 1)
        let locator = ToolLocator(searchDirs: [dir])
        #expect(throws: ToolError.javaMissing) { try locator.java() }
    }

    @Test func bundledRuntimeIsSearchedBeforeSystemDirs() throws {
        let resources = try makeDir()
        let bin = resources.appendingPathComponent("jre/bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let bundled = try makeExecutable("java", in: bin, exitCode: 0)
        let locator = ToolLocator(searchDirs: ToolLocator.bundledDirs(in: resources) + ToolLocator.defaultDirs)
        #expect(try locator.java().path == bundled.path)
    }

    @Test func noBundledDirsWithoutResources() {
        #expect(ToolLocator.bundledDirs(in: nil).isEmpty)
    }

    @Test func missingDotThrowsDotMissing() throws {
        let locator = ToolLocator(searchDirs: [try makeDir()])
        #expect(throws: ToolError.dotMissing) { try locator.dot() }
    }
}

@Suite struct ToolLocatorDefaultsTests {
    @Test func defaultDirsIncludeHomebrewOpenJDKKegs() {
        let paths = ToolLocator.defaultDirs.map(\.path)
        #expect(paths.contains("/opt/homebrew/opt/openjdk/bin"))
        #expect(paths.contains("/usr/local/opt/openjdk/bin"))
        let firstStub = paths.firstIndex(of: "/usr/bin") ?? .max
        #expect((paths.firstIndex(of: "/usr/local/opt/openjdk/bin") ?? .max) < firstStub)
    }
}
