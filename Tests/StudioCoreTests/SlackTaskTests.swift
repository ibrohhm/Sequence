import Foundation
import Testing
@testable import StudioCore

@Suite struct SlackTaskTests {
    let now = Date(timeIntervalSince1970: 1_794_700_000)

    func task(_ channel: String = "C1", _ ts: String = "1.1", tag: String = "todo", status: String = "Todo", archived: Bool = false,
              replies: Int? = nil, atTag: Int? = nil, lastReply: Date? = nil, tagged: String = "2026-01-01") -> SlackTask {
        SlackTask(tag: tag, channelID: channel, threadTS: ts, permalink: "p", channelName: nil, snippet: nil, replies: replies,
                  repliesAtTag: atTag, lastReply: lastReply, tagged: tagged, synced: nil, status: status, archived: archived)
    }

    @Test func idJoinsTagChannelAndThread() {
        #expect(task("C1", "1794536057.965929", tag: "saved").id == "saved/C1/1794536057.965929")
    }

    @Test func newRepliesIsTheDifferenceWhenPositive() {
        #expect(task(replies: 12, atTag: 10).newReplies == 2)
        #expect(task(replies: 10, atTag: 10).newReplies == nil)
        #expect(task(replies: 8, atTag: 10).newReplies == nil)
        #expect(task(replies: nil, atTag: 10).newReplies == nil)
        #expect(task(replies: 3, atTag: nil).newReplies == nil)
    }

    @Test func quietNeedsMoreThanFiveDays() {
        let day: TimeInterval = 86_400
        #expect(!task(lastReply: now - 5 * day).isQuiet(now: now))
        #expect(task(lastReply: now - 5 * day - 1).isQuiet(now: now))
    }

    @Test func theDoneColumnAndFactlessTasksAreNeverQuiet() {
        let old = now - 30 * 86_400
        #expect(!task(status: "Done", lastReply: old).isQuiet(now: now, doneColumn: "Done"))
        #expect(task(status: "Done", lastReply: old).isQuiet(now: now))
        #expect(!task(lastReply: nil).isQuiet(now: now))
    }

    @Test func aLaterTaggedDateIsTheReference() {
        let tagged = "2026-11-14"
        let taggedStart = ISO8601DateFormatter().date(from: "2026-11-14T00:00:00Z")!
        #expect(!task(lastReply: taggedStart - 40 * 86_400, tagged: tagged).isQuiet(now: taggedStart + 2 * 86_400))
        #expect(task(lastReply: taggedStart - 40 * 86_400, tagged: tagged).isQuiet(now: taggedStart + 6 * 86_400))
    }

    @Test func quietDaysCountsFromTheSameReferenceAsIsQuiet() {
        let day: TimeInterval = 86_400
        #expect(task(lastReply: now - 7 * day).quietDays(now: now) == 7)
        #expect(task(lastReply: now - 5 * day).quietDays(now: now) == nil)
        #expect(task(status: "Done", lastReply: now - 30 * day).quietDays(now: now, doneColumn: "Done") == nil)
        let taggedStart = ISO8601DateFormatter().date(from: "2026-11-14T00:00:00Z")!
        #expect(task(lastReply: taggedStart - 40 * day, tagged: "2026-11-14").quietDays(now: taggedStart + 6 * day) == 6)
    }
}
