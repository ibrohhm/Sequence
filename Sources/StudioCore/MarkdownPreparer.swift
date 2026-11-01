import Foundation

public enum DocumentKind: Equatable {
    case diagram, markdown

    public init(url: URL) {
        self = LibraryScanner.markdownExtensions.contains(url.pathExtension.lowercased()) ? .markdown : .diagram
    }
}

public struct PreparedMarkdown: Equatable {
    public let markdown: String
    public let diagrams: [String]
}

public enum MarkdownPreparer {
    private static let diagramLanguages: Set<String> = ["plantuml", "puml", "uml"]

    /// Marker left in the markdown where diagram `index` is to be inserted.
    public static func placeholder(_ index: Int) -> String { "@@PLANTUML-STUDIO-DIAGRAM-\(index)@@" }

    /// Strips frontmatter and swaps PlantUML fenced blocks for placeholders, returning their sources in order.
    public static func prepare(_ source: String) -> PreparedMarkdown {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var diagrams: [String] = []
        var i = frontmatterEnd(lines)
        while i < lines.count {
            guard let open = fenceOpening(lines[i]) else { out.append(lines[i]); i += 1; continue }
            guard let close = (i + 1..<lines.count).first(where: { isClosing(lines[$0], of: open) }) else {
                out.append(contentsOf: lines[i...])
                break
            }
            if diagramLanguages.contains(open.language) {
                let body = lines[(i + 1)..<close].joined(separator: "\n")
                diagrams.append(body.contains("@start") ? body : "@startuml\n\(body)\n@enduml")
                out.append(placeholder(diagrams.count - 1))
            } else {
                out.append(contentsOf: lines[i...close])
            }
            i = close + 1
        }
        return PreparedMarkdown(markdown: out.joined(separator: "\n"), diagrams: diagrams)
    }

    private static func frontmatterEnd(_ lines: [String]) -> Int {
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return 0 }
        for index in 1..<max(lines.count, 1) where ["---", "..."].contains(lines[index].trimmingCharacters(in: .whitespaces)) {
            return index + 1
        }
        return 0
    }

    private struct Fence { let marker: Character; let count: Int; let language: String }

    private static func fenceOpening(_ line: String) -> Fence? {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3, let marker = trimmed.first, marker == "`" || marker == "~" else { return nil }
        let count = trimmed.prefix(while: { $0 == marker }).count
        guard count >= 3 else { return nil }
        let info = trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces)
        if marker == "`" && info.contains("`") { return nil }
        let language = info.split(separator: " ").first.map { $0.lowercased() } ?? ""
        return Fence(marker: marker, count: count, language: language)
    }

    private static func isClosing(_ line: String, of fence: Fence) -> Bool {
        let trimmed = line.drop(while: { $0 == " " })
        guard line.count - trimmed.count <= 3 else { return false }
        let run = trimmed.prefix(while: { $0 == fence.marker })
        return run.count >= fence.count && trimmed.dropFirst(run.count).allSatisfy { $0 == " " }
    }
}
