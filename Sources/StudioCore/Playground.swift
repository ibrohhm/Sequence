import Foundation

/// The scratch files behind the playground: one per document kind, kept between launches.
public enum Playground {
    public static func starter(_ kind: DocumentKind) -> String {
        switch kind {
        case .diagram:
            "@startuml\nAlice -> Bob: Hello\nBob --> Alice: Hi\n@enduml\n"
        case .markdown:
            "# Playground\n\nWrite markdown here. Diagrams render inline:\n\n```plantuml\nAlice -> Bob: Hello\nBob --> Alice: Hi\n```\n"
        }
    }

    /// Application Support folder that holds the scratch files.
    public static func defaultDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sequence/Playground", isDirectory: true)
    }

    public static func fileURL(for kind: DocumentKind, in directory: URL) -> URL {
        directory.appendingPathComponent(kind == .diagram ? "playground.puml" : "playground.md")
    }

    /// Returns the scratch file for `kind`, creating it with the starter text if missing and never overwriting it.
    public static func ensureFile(for kind: DocumentKind, in directory: URL) throws -> URL {
        let url = fileURL(for: kind, in: directory)
        if !FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try starter(kind).write(to: url, atomically: true, encoding: .utf8)
        }
        return url
    }

    public static func contains(_ url: URL, in directory: URL) -> Bool {
        url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL
    }
}
