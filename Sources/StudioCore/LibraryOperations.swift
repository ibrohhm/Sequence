import Foundation

public enum LibraryOperationError: Error, Equatable { case alreadyExists, invalidName }

public enum LibraryOperations {
    /// Creates a starter diagram, adding `.puml` when `named` has no diagram extension.
    public static func createFile(named name: String, in folder: URL) throws -> URL {
        let trimmed = try validated(name)
        let fileName = LibraryScanner.extensions.contains((trimmed as NSString).pathExtension.lowercased()) ? trimmed : trimmed + ".puml"
        let url = folder.appendingPathComponent(fileName)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryOperationError.alreadyExists }
        try "@startuml\n@enduml\n".write(to: url, atomically: true, encoding: .utf8)
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

    /// Moves the item to the Trash.
    public static func delete(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    private static func validated(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { throw LibraryOperationError.invalidName }
        return trimmed
    }
}
