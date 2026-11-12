import Foundation

public enum LibraryOperationError: Error, Equatable { case alreadyExists, invalidName, invalidMove }

public enum LibraryOperations {
    /// Creates a starter file, adding `.puml` when `named` has no supported extension.
    public static func createFile(named name: String, in folder: URL) throws -> URL {
        let trimmed = try validated(name)
        let fileName = LibraryScanner.extensions.contains((trimmed as NSString).pathExtension.lowercased()) ? trimmed : trimmed + ".puml"
        let url = folder.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryOperationError.alreadyExists }
        let starter = DocumentKind(url: url) == .markdown ? "# \(url.deletingPathExtension().lastPathComponent)\n" : "@startuml\n@enduml\n"
        try starter.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public static func createFolder(named name: String, in folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(try validated(name))
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryOperationError.alreadyExists }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    public static func rename(_ url: URL, to newName: String) throws -> URL {
        let target = url.deletingLastPathComponent().appendingPathComponent(try validated(newName))
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryOperationError.alreadyExists }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// Moves a file or folder into `folder`; a move into its current parent changes nothing.
    public static func move(_ url: URL, into folder: URL) throws -> URL {
        let source = url.standardizedFileURL.path
        let destination = folder.standardizedFileURL.path
        guard destination != source, !destination.hasPrefix(source + "/") else { throw LibraryOperationError.invalidMove }
        guard url.deletingLastPathComponent().standardizedFileURL.path != destination else { return url }
        let target = folder.appendingPathComponent(url.lastPathComponent)
        guard !FileManager.default.fileExists(atPath: target.path) else { throw LibraryOperationError.alreadyExists }
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    /// Where `url` ends up after `old` moved to `new`, or nil when `url` is not `old` or inside it.
    public static func relocated(_ url: URL, from old: URL, to new: URL) -> URL? {
        let path = url.standardizedFileURL.path, oldPath = old.standardizedFileURL.path
        if path == oldPath { return new }
        guard path.hasPrefix(oldPath + "/") else { return nil }
        return URL(fileURLWithPath: new.standardizedFileURL.path + path.dropFirst(oldPath.count))
    }

    /// Moves the item to the Trash.
    public static func delete(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    /// The folder a new item goes in: the focused folder, the folder of a focused file, else the root.
    public static func targetFolder(for focus: URL?, root: URL) -> URL {
        guard let focus else { return root }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: focus.path, isDirectory: &isDirectory) else { return root }
        return isDirectory.boolValue ? focus : focus.deletingLastPathComponent()
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { throw LibraryOperationError.invalidName }
        return trimmed
    }
}
