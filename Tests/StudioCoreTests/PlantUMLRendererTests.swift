import Testing
import Foundation
import Network
@testable import StudioCore

private let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
private let jarURL = repoRoot.appendingPathComponent("App/Resources/plantuml.jar")

private func makeRenderer() throws -> PlantUMLRenderer {
    let locator = ToolLocator()
    let java = try locator.java()
    return PlantUMLRenderer(javaURL: java, jarURL: jarURL, dotURL: try? locator.dot())
}

private func tempDir() throws -> URL {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}

private func svgText(_ result: RenderResult) -> String? {
    if case .svg(let data) = result { return String(decoding: data, as: UTF8.self) }
    return nil
}

private let sequence = "@startuml\nA -> B: hi\n@enduml\n"

@Suite(.serialized) struct PlantUMLRendererTests {
    @Test func rendersSimpleSequenceToSVG() async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render(sequence, baseDirectory: try tempDir())
        #expect(svgText(result)?.contains("<svg") == true)
        await renderer.shutdown()
    }

    @Test func syntaxErrorReturnsFailureWithMessage() async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render("@startuml\nthis is ((( not valid\n@enduml\n", baseDirectory: try tempDir())
        guard case .failure(let message) = result else { Issue.record("expected failure, got \(result)"); return }
        #expect(!message.isEmpty)
        await renderer.shutdown()
    }

    @Test func emptySourceReturnsFailureNotHang() async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render("", baseDirectory: try tempDir())
        guard case .failure = result else { Issue.record("expected failure, got \(result)"); return }
        await renderer.shutdown()
    }

    @Test func unicodeSourceRenders() async throws {
        let renderer = try makeRenderer()
        let source = "@startuml\nparticipant \"Pembayaran 💳 é\" as P\nP -> P: ok\n@enduml\n"
        let result = await renderer.render(source, baseDirectory: try tempDir())
        #expect(svgText(result)?.contains("Pembayaran 💳 é") == true)
        await renderer.shutdown()
    }

    @Test func secondRenderIsFast() async throws {
        let renderer = try makeRenderer()
        let dir = try tempDir()
        _ = await renderer.render(sequence, baseDirectory: dir)
        let start = ContinuousClock.now
        let result = await renderer.render("@startuml\nB -> C: again\n@enduml\n", baseDirectory: dir)
        let elapsed = ContinuousClock.now - start
        #expect(svgText(result) != nil)
        #expect(elapsed < .milliseconds(500))
        await renderer.shutdown()
    }

    @Test func relativeIncludeResolvesAgainstBaseDirectory() async throws {
        let dir = try tempDir()
        try "A -> B: from include\n".write(to: dir.appendingPathComponent("part.puml"), atomically: true, encoding: .utf8)
        let renderer = try makeRenderer()
        let result = await renderer.render("@startuml\n!include part.puml\n@enduml\n", baseDirectory: dir)
        #expect(svgText(result)?.contains("from include") == true)
        await renderer.shutdown()
    }

    @Test func remoteIncludeIsBlockedWithoutNetworkRequest() async throws {
        let hits = ConnectionCounter()
        let listener = try NWListener(using: .tcp, on: .any)
        listener.newConnectionHandler = { conn in hits.increment(); conn.cancel() }
        listener.start(queue: .global())
        while listener.port == nil { try await Task.sleep(for: .milliseconds(20)) }
        let port = listener.port!.rawValue
        let renderer = try makeRenderer()
        let result = await renderer.render("@startuml\n!includeurl http://127.0.0.1:\(port)/x.puml\nA -> B\n@enduml\n", baseDirectory: try tempDir())
        try await Task.sleep(for: .milliseconds(300))
        listener.cancel()
        #expect(hits.count == 0)
        if case .failure = result {} else { #expect(svgText(result)?.contains("A -> B") != true || svgText(result)?.lowercased().contains("error") == true) }
        await renderer.shutdown()
    }

    @Test func cancelledRenderReturnsSupersededAndNextRenderWorks() async throws {
        let renderer = try makeRenderer()
        let dir = try tempDir()
        let task = Task { await renderer.render(sequence, baseDirectory: dir) }
        task.cancel()
        let cancelled = await task.value
        #expect(cancelled == .superseded)
        let next = await renderer.render(sequence, baseDirectory: dir)
        #expect(svgText(next) != nil)
        await renderer.shutdown()
    }

    @Test func changingBaseDirectoryRestartsProcessAndStillRenders() async throws {
        let renderer = try makeRenderer()
        let first = await renderer.render(sequence, baseDirectory: try tempDir())
        let second = await renderer.render(sequence, baseDirectory: try tempDir())
        #expect(svgText(first) != nil)
        #expect(svgText(second) != nil)
        await renderer.shutdown()
    }

    @Test func concurrentRendersEachGetTheirOwnDiagram() async throws {
        let renderer = try makeRenderer()
        let dir = try tempDir()
        async let old = renderer.render("@startuml\nOLD -> OLD: first\n@enduml\n", baseDirectory: dir)
        async let new = renderer.render("@startuml\nNEW -> NEW: second\n@enduml\n", baseDirectory: dir)
        let (a, b) = await (old, new)
        #expect(svgText(a)?.contains("OLD") == true)
        #expect(svgText(b)?.contains("NEW") == true)
        await renderer.shutdown()
    }

    @Test(arguments: [
        "@startuml\nA -> B\n",
        "A -> B : see @startuml\n",
        "@startuml\nA -> B\n@enduml\n@startuml\nC ->",
    ])
    func incompleteBlocksFailFastInsteadOfHanging(source: String) async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render(source, baseDirectory: try tempDir())
        guard case .failure(let message) = result else { Issue.record("expected failure for \(source.debugDescription), got \(result)"); return }
        #expect(!message.isEmpty)
        let next = await renderer.render(sequence, baseDirectory: try tempDir())
        #expect(svgText(next) != nil)
        await renderer.shutdown()
    }

    @Test func secondStartResetsOpenBlockAndRendersOnce() async throws {
        let renderer = try makeRenderer()
        let dir = try tempDir()
        let result = await renderer.render("@startuml\nA -> B\n@startuml\nC -> D: kept\n@enduml\n", baseDirectory: dir)
        #expect(svgText(result)?.contains("kept") == true)
        let next = await renderer.render(sequence, baseDirectory: dir)
        #expect(svgText(next)?.contains("hi") == true)
        await renderer.shutdown()
    }

    @Test func slowRenderIsStoppedByWatchdogAndNextRenderRecovers() async throws {
        let locator = ToolLocator()
        let impatient = PlantUMLRenderer(javaURL: try locator.java(), jarURL: jarURL, dotURL: nil, timeout: .milliseconds(1))
        let result = await impatient.render(sequence, baseDirectory: try tempDir())
        guard case .failure(let message) = result else { Issue.record("expected timeout failure, got \(result)"); return }
        #expect(message.contains("too long"))
        await impatient.shutdown()
    }

    @Test func missingIncludeFileIsReportedNotWelcomePage() async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render("@startuml\n!include nope.puml\nA -> B\n@enduml\n", baseDirectory: try tempDir())
        guard case .failure(let message) = result else { Issue.record("expected failure, got \(result)"); return }
        #expect(message.lowercased().contains("include"))
        await renderer.shutdown()
    }

    @Test(arguments: [
        "@startuml\n!$d = %load_json(\"http://example.com/x.json\")\nA -> B\n@enduml\n",
        "@startuml\nA -> B : <img:https://example.com/x.png>\n@enduml\n",
    ])
    func otherRemoteFetchesAreBlockedBeforeJavaSeesThem(source: String) async throws {
        let renderer = try makeRenderer()
        let result = await renderer.render(source, baseDirectory: try tempDir())
        guard case .failure(let message) = result else { Issue.record("expected failure, got \(result)"); return }
        #expect(message.lowercased().contains("remote"))
        await renderer.shutdown()
    }

    @Test func cancelledRenderDoesNotKillSessionOfNextRender() async throws {
        let renderer = try makeRenderer()
        let first = Task { await renderer.render(sequence, baseDirectory: try! tempDir()) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        let second = await renderer.render(sequence, baseDirectory: try tempDir())
        #expect(svgText(second) != nil)
        _ = await first.value
        await renderer.shutdown()
    }

    @Test func rendererSurvivesJavaProcessBeingKilledExternally() async throws {
        let renderer = try makeRenderer()
        let dir = try tempDir()
        _ = await renderer.render(sequence, baseDirectory: dir)
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-9", "-f", "PLANTUML-STUDIO-END"]
        try kill.run(); kill.waitUntilExit()
        _ = await renderer.render(sequence, baseDirectory: dir)
        let recovered = await renderer.render(sequence, baseDirectory: dir)
        #expect(svgText(recovered) != nil)
        await renderer.shutdown()
    }

    @Test func exportPNGReturnsPNGBytes() async throws {
        let locator = ToolLocator()
        let data = await exportPNG(source: sequence, baseDirectory: try tempDir(), javaURL: try locator.java(), jarURL: jarURL, dotURL: try? locator.dot())
        #expect(data?.prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }
}

private final class ConnectionCounter: @unchecked Sendable {
    private let lock = NSLock(); private var n = 0
    func increment() { lock.lock(); n += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return n }
}
