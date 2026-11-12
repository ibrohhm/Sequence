import Foundation

/// Which sidebar folders the user opened or collapsed, by path.
public struct FolderExpansion: Equatable {
    public private(set) var states: [String: Bool]

    public init(states: [String: Bool] = [:]) { self.states = states }

    /// The saved choice for `path`, else `fallback`.
    public func isExpanded(_ path: String, default fallback: Bool) -> Bool { states[path] ?? fallback }

    public mutating func set(_ path: String, expanded: Bool) { states[path] = expanded }

    /// Re-keys the choices of `old` and everything under it to `new`.
    public mutating func remap(from old: String, to new: String) {
        var result: [String: Bool] = [:]
        for (path, value) in states {
            if path == old { result[new] = value }
            else if path.hasPrefix(old + "/") { result[new + path.dropFirst(old.count)] = value }
            else { result[path] = value }
        }
        states = result
    }
}
