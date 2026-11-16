import Foundation

public enum SlackTagKind: String, Sendable { case board, list }

/// Which of Slack's own lists also feeds a tag.
public enum SlackList: String, Sendable { case none, todo, saved }

/// A named source of Slack threads with its own page: a board of columns or a plain list.
public struct SlackTag: Identifiable, Equatable, Sendable {
    public let id: String
    public var name: String
    public var kind: SlackTagKind
    public var slackList: SlackList
    public var reactions: [String]
    public var columns: [String]
    public var position: Int
    public var builtin: Bool

    public init(id: String, name: String, kind: SlackTagKind, slackList: SlackList, reactions: [String], columns: [String], position: Int, builtin: Bool) {
        self.id = id
        self.name = name
        self.kind = kind
        self.slackList = slackList
        self.reactions = reactions
        self.columns = columns
        self.position = position
        self.builtin = builtin
    }
}

public enum SlackTagRules {
    /// A lowercase dashed id from a name, made unique against `existing` with a numeric suffix.
    public static func slug(for name: String, existing: Set<String>) -> String {
        var slug = ""
        for scalar in name.lowercased().unicodeScalars {
            let alphanumeric = scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar))
            if alphanumeric { slug.unicodeScalars.append(scalar) } else if !slug.hasSuffix("-") { slug += "-" }
        }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "tag" }
        guard existing.contains(slug) else { return slug }
        var number = 2
        while existing.contains("\(slug)-\(number)") { number += 1 }
        return "\(slug)-\(number)"
    }

    /// A message describing the first problem with a tag's settings, or nil when they are fine.
    public static func validate(name: String, kind: SlackTagKind, reactions: [String], columns: [String]) -> String? {
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give the tag a name." }
        for reaction in reactions where reaction.range(of: "^[a-z0-9_+-]+$", options: .regularExpression) == nil {
            return "\"\(reaction)\" is not an emoji name (lowercase letters, digits, _ + - only, no colons)."
        }
        switch kind {
        case .list:
            if !columns.isEmpty { return "A list has no columns." }
        case .board:
            if columns.isEmpty { return "A board needs at least one column." }
            if columns.count > 8 { return "A board can have at most 8 columns." }
            var seen = Set<String>()
            for column in columns {
                let trimmed = column.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { return "A column needs a name." }
                if !seen.insert(trimmed.lowercased()).inserted { return "Two columns are named \"\(trimmed)\"." }
            }
        }
        return nil
    }
}
