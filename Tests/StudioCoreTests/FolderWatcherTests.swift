import Testing
import Foundation
@testable import StudioCore

private final class Flag: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func hit() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}

private func tempRoot() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("watch \(UUID().uuidString)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir.resolvingSymlinksInPath()
}

@Suite(.serialized) struct FolderWatcherTests {
    @Test func watcherFiresWhenFileAdded() async throws {
        let root = try tempRoot()
        let flag = Flag()
        let watcher = FolderWatcher(root: root) { flag.hit() }
        try await Task.sleep(for: .milliseconds(500))
        try "x".write(to: root.appendingPathComponent("new.puml"), atomically: true, encoding: .utf8)
        for _ in 0..<60 where flag.count == 0 { try await Task.sleep(for: .milliseconds(50)) }
        #expect(flag.count > 0)
        watcher.stop()
    }

    @Test func watcherStopSilencesCallbacks() async throws {
        let root = try tempRoot()
        let flag = Flag()
        let watcher = FolderWatcher(root: root) { flag.hit() }
        try await Task.sleep(for: .milliseconds(500))
        watcher.stop()
        let before = flag.count
        try "x".write(to: root.appendingPathComponent("late.puml"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1))
        #expect(flag.count == before)
    }
}
