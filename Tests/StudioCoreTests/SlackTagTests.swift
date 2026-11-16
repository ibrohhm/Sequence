import Foundation
import Testing
@testable import StudioCore

@Suite struct SlackTagTests {
    func tag(_ id: String = "review", kind: SlackTagKind = .board, columns: [String] = ["Open", "Done"]) -> SlackTag {
        SlackTag(id: id, name: id, kind: kind, slackList: .none, reactions: [], columns: columns, position: 0, builtin: false)
    }

    func task(_ ts: String, tag: String = "review", status: String, archived: Bool = false, lastReply: Date? = nil) -> SlackTask {
        SlackTask(tag: tag, channelID: "C1", threadTS: ts, permalink: "p", channelName: nil, snippet: nil, replies: nil, repliesAtTag: nil,
                  lastReply: lastReply, tagged: "2026-01-01", synced: nil, status: status, archived: archived)
    }

    @Test func slugMakesALowercaseDashedId() {
        #expect(SlackTagRules.slug(for: "Code Review", existing: []) == "code-review")
        #expect(SlackTagRules.slug(for: "  To-do!! ", existing: []) == "to-do")
    }

    @Test func slugAddsASuffixOnCollisionAndFallsBack() {
        #expect(SlackTagRules.slug(for: "Code Review", existing: ["code-review"]) == "code-review-2")
        #expect(SlackTagRules.slug(for: "Code Review", existing: ["code-review", "code-review-2"]) == "code-review-3")
        #expect(SlackTagRules.slug(for: "🎫 !!", existing: []) == "tag")
    }

    @Test func validateAcceptsAGoodTag() {
        #expect(SlackTagRules.validate(name: "Review", kind: .board, reactions: ["eyes", "loading1"], columns: ["Open", "Done"]) == nil)
        #expect(SlackTagRules.validate(name: "Links", kind: .list, reactions: [], columns: []) == nil)
    }

    @Test(arguments: [
        ("", SlackTagKind.board, [String](), ["Open"]),
        ("Links", SlackTagKind.list, [String](), ["Open"]),
        ("Review", SlackTagKind.board, [String](), []),
        ("Review", SlackTagKind.board, [String](), ["1", "2", "3", "4", "5", "6", "7", "8", "9"]),
        ("Review", SlackTagKind.board, [String](), ["Open", "open"]),
        ("Review", SlackTagKind.board, [String](), ["Open", "  "]),
        ("Review", SlackTagKind.board, ["Bad Name"], ["Open"]),
        ("Review", SlackTagKind.board, [":ticket:"], ["Open"]),
    ])
    func validateRejectsBadInput(name: String, kind: SlackTagKind, reactions: [String], columns: [String]) {
        #expect(SlackTagRules.validate(name: name, kind: kind, reactions: reactions, columns: columns) != nil)
    }

    @Test func aBoardGroupsCardsByColumnInOrder() {
        let groups = SlackBoard.groups([task("1.1", status: "Done"), task("2.2", status: "Open")], for: tag())
        #expect(groups.map(\.name) == ["Open", "Done"])
        #expect(groups[0].tasks.map(\.threadTS) == ["2.2"])
        #expect(groups[1].tasks.map(\.threadTS) == ["1.1"])
    }

    @Test func aCardWithAnUnknownStatusShowsInTheFirstColumn() {
        let groups = SlackBoard.groups([task("1.1", status: "Gone")], for: tag())
        #expect(groups[0].tasks.map(\.threadTS) == ["1.1"])
        #expect(groups[1].tasks.isEmpty)
    }

    @Test func archivedCardsAndOtherTagsAreLeftOut() {
        let groups = SlackBoard.groups([task("1.1", status: "Open", archived: true), task("2.2", tag: "other", status: "Open")], for: tag())
        #expect(groups.allSatisfy { $0.tasks.isEmpty })
    }

    @Test func cardsAreNewestActivityFirst() {
        let old = Date(timeIntervalSince1970: 1_794_000_000)
        let groups = SlackBoard.groups([task("1.1", status: "Open", lastReply: old), task("2.2", status: "Open", lastReply: old + 100)], for: tag())
        #expect(groups[0].tasks.map(\.threadTS) == ["2.2", "1.1"])
    }

    @Test func aListIsOneGroupOfAllActiveCards() {
        let groups = SlackBoard.groups([task("1.1", status: ""), task("2.2", status: "", archived: true)], for: tag(kind: .list, columns: []))
        #expect(groups.count == 1)
        #expect(groups[0].name == "")
        #expect(groups[0].tasks.map(\.threadTS) == ["1.1"])
    }
}
