import Testing
import Foundation
@testable import StudioCore

@Suite struct MarkdownPreparerTests {
    @Test func documentKindFollowsExtension() {
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/x.md")) == .markdown)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/x.MD")) == .markdown)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/x.puml")) == .diagram)
        #expect(DocumentKind(url: URL(fileURLWithPath: "/a/x.wsd")) == .diagram)
    }

    @Test func frontmatterIsStripped() {
        let out = MarkdownPreparer.prepare("---\ntitle: RFC\n---\n# Hi\n")
        #expect(out.markdown == "# Hi\n")
    }

    @Test func dashesNotAtTopAreKept() {
        let out = MarkdownPreparer.prepare("# Hi\n\n---\n\ntext\n")
        #expect(out.markdown == "# Hi\n\n---\n\ntext\n")
    }

    @Test func unclosedFrontmatterIsKept() {
        let src = "---\ntitle: RFC\n# Hi\n"
        #expect(MarkdownPreparer.prepare(src).markdown == src)
    }

    @Test func plantumlFenceBecomesPlaceholderAndDiagram() {
        let src = "before\n\n```plantuml\n@startuml\nA -> B\n@enduml\n```\n\nafter\n"
        let out = MarkdownPreparer.prepare(src)
        #expect(out.diagrams == ["@startuml\nA -> B\n@enduml"])
        #expect(out.markdown == "before\n\n\(MarkdownPreparer.placeholder(0))\n\nafter\n")
    }

    @Test func pumlAndUmlInfoStringsAreDiagramsCaseInsensitive() {
        let src = "```puml\n@startuml\n@enduml\n```\n~~~UML\n@startuml\n@enduml\n~~~\n"
        #expect(MarkdownPreparer.prepare(src).diagrams.count == 2)
    }

    @Test func fenceWithoutStartTagIsWrapped() {
        let out = MarkdownPreparer.prepare("```plantuml\nA -> B\n```\n")
        #expect(out.diagrams == ["@startuml\nA -> B\n@enduml"])
    }

    @Test func otherLanguagesStayCode() {
        let src = "```go\nfunc main() {}\n```\n"
        let out = MarkdownPreparer.prepare(src)
        #expect(out.diagrams.isEmpty)
        #expect(out.markdown == src)
    }

    @Test func plantumlFenceInsideLongerFenceIsNotExtracted() {
        let src = "````md\n```plantuml\nA -> B\n```\n````\n"
        let out = MarkdownPreparer.prepare(src)
        #expect(out.diagrams.isEmpty)
        #expect(out.markdown == src)
    }

    @Test func unclosedFenceStaysAsIs() {
        let src = "```plantuml\nA -> B\n"
        let out = MarkdownPreparer.prepare(src)
        #expect(out.diagrams.isEmpty)
        #expect(out.markdown == src)
    }

    @Test func multipleDiagramsGetIncreasingPlaceholders() {
        let src = "```plantuml\nA -> B\n```\n\n```plantuml\nC -> D\n```\n"
        let out = MarkdownPreparer.prepare(src)
        #expect(out.diagrams.count == 2)
        #expect(out.markdown.contains(MarkdownPreparer.placeholder(0)))
        #expect(out.markdown.contains(MarkdownPreparer.placeholder(1)))
    }
}
