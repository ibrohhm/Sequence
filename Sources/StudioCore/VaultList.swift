import Foundation

/// A named folder the app can switch to.
public struct Vault: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public var path: String
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }
}

/// The user's vaults, saved as JSON.
public struct VaultList: Codable, Equatable, Sendable {
    public private(set) var vaults: [Vault] = []

    public init() {}

    /// Adds `folder` as a vault, or returns the existing vault for the same folder.
    @discardableResult
    public mutating func add(folder: URL) -> Vault {
        let path = folder.standardizedFileURL.path
        if let existing = vaults.first(where: { $0.path == path }) { return existing }
        let vault = Vault(id: UUID(), name: folder.standardizedFileURL.lastPathComponent, path: path)
        vaults.append(vault)
        return vault
    }

    /// Creates the folder `name` inside `base` and adds it as a vault.
    public mutating func create(named name: String, in base: URL) throws -> Vault {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.hasPrefix(".") else { throw LibraryOperationError.invalidName }
        let url = base.appendingPathComponent(trimmed, isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else { throw LibraryOperationError.alreadyExists }
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return add(folder: url)
    }

    /// Forgets the vault; its files stay on disk.
    public mutating func remove(_ id: UUID) {
        vaults.removeAll { $0.id == id }
    }

    public mutating func rename(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let index = vaults.firstIndex(where: { $0.id == id }) else { return }
        vaults[index].name = trimmed
    }

    public static func load(from file: URL) -> VaultList {
        (try? JSONDecoder().decode(VaultList.self, from: Data(contentsOf: file))) ?? VaultList()
    }

    public func save(to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(self).write(to: file, options: .atomic)
    }

    /// Application Support file that holds the list.
    public static func defaultFile() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sequence/vaults.json")
    }

    /// ~/Documents/Sequence, where new vaults are created.
    public static func defaultBase() -> URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sequence", isDirectory: true)
    }
}
