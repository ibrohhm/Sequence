import Foundation

public struct FileNode: Identifiable, Hashable {
    public let id: URL
    public let name: String
    public let isDirectory: Bool
    public var children: [FileNode]?

    public init(id: URL, name: String, isDirectory: Bool, children: [FileNode]? = nil) {
        self.id = id
        self.name = name
        self.isDirectory = isDirectory
        self.children = children
    }
}

public enum LibraryScanner {
    public static let diagramExtensions: Set<String> = ["puml", "plantuml", "pu", "wsd"]
    public static let markdownExtensions: Set<String> = ["md"]
    public static let extensions = diagramExtensions.union(markdownExtensions)

    /// Returns the diagram and markdown files under `root`, with folders first and each group sorted A–Z ignoring case.
    public static func scan(_ root: URL) throws -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        let entries = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folders: [FileNode] = []
        var files: [FileNode] = []
        for url in entries {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isDirectory == true {
                if values.isSymbolicLink == true { continue }
                let children = try scan(url)
                if !children.isEmpty { folders.append(FileNode(id: url, name: url.lastPathComponent, isDirectory: true, children: children)) }
            } else if extensions.contains(url.pathExtension.lowercased()) {
                files.append(FileNode(id: url, name: url.lastPathComponent, isDirectory: false))
            }
        }
        let byName: (FileNode, FileNode) -> Bool = { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return folders.sorted(by: byName) + files.sorted(by: byName)
    }
}
