import Foundation

public enum SlackStatus: String, CaseIterable, Sendable {
    case todo, inprogress, blocked, done

    public var title: String {
        switch self {
        case .todo: "Todo"
        case .inprogress: "In progress"
        case .blocked: "Blocked"
        case .done: "Done"
        }
    }
}

/// One tracked Slack thread, as stored in the tasks database.
public struct SlackTask: Identifiable, Equatable, Sendable {
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
    public var status: SlackStatus
    public var archived: Bool
    public var summary: String?
    public var nextAction: String?
    public var summaryReplies: Int?

    public init(channelID: String, threadTS: String, permalink: String, channelName: String?, snippet: String?, replies: Int?,
                repliesAtTag: Int?, lastReply: Date?, tagged: String, synced: String?, status: SlackStatus, archived: Bool,
                summary: String? = nil, nextAction: String? = nil, summaryReplies: Int? = nil) {
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

    public var id: String { "\(channelID)/\(threadTS)" }

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

    /// True when an open thread with known activity has been silent for more than `days` days.
    public func isQuiet(now: Date, days: Int = 5) -> Bool {
        guard status != .done, let lastReply else { return false }
        return now.timeIntervalSince(max(lastReply, taggedStart)) > Double(days) * 86_400
    }

    /// Whole days of silence when the task is quiet, measured the same way as `isQuiet`.
    public func quietDays(now: Date, days: Int = 5) -> Int? {
        guard isQuiet(now: now, days: days), let lastReply else { return nil }
        return Int(now.timeIntervalSince(max(lastReply, taggedStart)) / 86_400)
    }
}

public enum SlackBoard {
    /// Active tasks grouped by status, newest activity first.
    public static func columns(_ tasks: [SlackTask]) -> [SlackStatus: [SlackTask]] {
        var result = Dictionary(uniqueKeysWithValues: SlackStatus.allCases.map { ($0, [SlackTask]()) })
        for task in tasks where !task.archived { result[task.status, default: []].append(task) }
        for status in SlackStatus.allCases {
            result[status]?.sort { $0.activity != $1.activity ? $0.activity > $1.activity : $0.id < $1.id }
        }
        return result
    }
}
