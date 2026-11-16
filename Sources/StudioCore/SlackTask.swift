import Foundation

/// One tracked Slack thread, as stored in the tasks database.
public struct SlackTask: Identifiable, Equatable, Sendable {
    public let tag: String
    public let channelID: String
    public let threadTS: String
    public var permalink: String
    public var channelName: String?
    public var snippet: String?
    public var replies: Int?
    public var repliesAtTag: Int?
    public var lastReply: Date?
    public var tagged: String
    public var synced: String?
    public var status: String
    public var archived: Bool
    public var summary: String?
    public var nextAction: String?
    public var summaryReplies: Int?

    public init(tag: String, channelID: String, threadTS: String, permalink: String, channelName: String?, snippet: String?, replies: Int?,
                repliesAtTag: Int?, lastReply: Date?, tagged: String, synced: String?, status: String, archived: Bool,
                summary: String? = nil, nextAction: String? = nil, summaryReplies: Int? = nil) {
        self.tag = tag
        self.channelID = channelID
        self.threadTS = threadTS
        self.permalink = permalink
        self.channelName = channelName
        self.snippet = snippet
        self.replies = replies
        self.repliesAtTag = repliesAtTag
        self.lastReply = lastReply
        self.tagged = tagged
        self.synced = synced
        self.status = status
        self.archived = archived
        self.summary = summary
        self.nextAction = nextAction
        self.summaryReplies = summaryReplies
    }

    public var id: String { "\(tag)/\(channelID)/\(threadTS)" }

    /// Replies that arrived since the thread was tagged, when known and above zero.
    public var newReplies: Int? {
        guard let replies, let repliesAtTag, replies > repliesAtTag else { return nil }
        return replies - repliesAtTag
    }

    var taggedStart: Date {
        ISO8601DateFormatter().date(from: tagged + "T00:00:00Z") ?? .distantPast
    }

    /// The later of the last reply and the day it was tagged.
    var activity: Date { max(lastReply ?? .distantPast, taggedStart) }

    /// True when a thread outside the done column, with known activity, has been silent for more than `days` days.
    public func isQuiet(now: Date, days: Int = 5, doneColumn: String? = nil) -> Bool {
        guard status != doneColumn, let lastReply else { return false }
        return now.timeIntervalSince(max(lastReply, taggedStart)) > Double(days) * 86_400
    }

    /// Whole days of silence when the task is quiet, measured the same way as `isQuiet`.
    public func quietDays(now: Date, days: Int = 5, doneColumn: String? = nil) -> Int? {
        guard isQuiet(now: now, days: days, doneColumn: doneColumn), let lastReply else { return nil }
        return Int(now.timeIntervalSince(max(lastReply, taggedStart)) / 86_400)
    }
}

public enum SlackBoard {
    /// A tag's active cards grouped by column (a list is one unnamed group), newest activity first.
    /// A card whose status matches no column is shown in the first column.
    public static func groups(_ tasks: [SlackTask], for tag: SlackTag) -> [(name: String, tasks: [SlackTask])] {
        let mine = tasks.filter { $0.tag == tag.id && !$0.archived }
            .sorted { $0.activity != $1.activity ? $0.activity > $1.activity : $0.id < $1.id }
        guard tag.kind == .board, let first = tag.columns.first else { return [(name: "", tasks: mine)] }
        return tag.columns.map { column in
            (name: column, tasks: mine.filter { tag.columns.contains($0.status) ? $0.status == column : column == first })
        }
    }
}
