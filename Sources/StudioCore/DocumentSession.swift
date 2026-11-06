import Foundation

public enum ExternalChange: Equatable { case none, reloaded, conflict, fileMissing }

/// Editing state for one open diagram file: dirty tracking, explicit save, and external-change handling.
@MainActor public final class DocumentSession: ObservableObject {
    @Published public var text: String
    public private(set) var url: URL
    @Published private var savedText: String
    private var acknowledgedDisk: String?

    public var isDirty: Bool { text != savedText }

    public init(url: URL) throws {
        let content = try String(contentsOf: url, encoding: .utf8)
        self.url = url
        self.text = content
        self.savedText = content
    }

    public func save() throws {
        try text.write(to: url, atomically: true, encoding: .utf8)
        savedText = text
        acknowledgedDisk = nil
    }

    public func diskDidChange() -> ExternalChange {
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else { return .fileMissing }
        if disk == savedText { return .none }
        if !isDirty {
            text = disk
            savedText = disk
            return .reloaded
        }
        if disk == acknowledgedDisk { return .none }
        return .conflict
    }

    public func reloadFromDisk() throws {
        let disk = try String(contentsOf: url, encoding: .utf8)
        text = disk
        savedText = disk
        acknowledgedDisk = nil
    }

    /// Points the session at a renamed or moved file, keeping unsaved text.
    public func relocate(to newURL: URL) { url = newURL }

    public func keepMine() {
        acknowledgedDisk = try? String(contentsOf: url, encoding: .utf8)
    }
}
