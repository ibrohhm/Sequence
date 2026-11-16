import Foundation
import Testing
@testable import StudioCore

@Suite struct SlackTagTests {
    func tag(_ id: String = "review", name: String? = nil, kind: SlackTagKind = .board) -> SlackTag {
        SlackTag(id: id, name: name ?? id, kind: kind, slackList: .none, reactions: [], columns: kind == .board ? SlackColumns.all : [], position: 0, builtin: false)
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

    @Test func slugNeverTakesThePageIdOfTheTasksPage() {
        #expect(SlackTagRules.slug(for: "Tasks", existing: []) == "tasks-2")
        #expect(SlackTagRules.slug(for: "tasks", existing: ["tasks-2"]) == "tasks-3")
    }

    @Test func validateAcceptsAGoodTag() {
        #expect(SlackTagRules.validate(name: "Review", reactions: ["eyes", "loading1"]) == nil)
        #expect(SlackTagRules.validate(name: "Links", reactions: []) == nil)
    }

    @Test(arguments: [("", [String]()), ("Review", ["Bad Name"]), ("Review", [":ticket:"])])
    func validateRejectsBadInput(name: String, reactions: [String]) {
        #expect(SlackTagRules.validate(name: name, reactions: reactions) != nil)
    }

    @Test func theStandardColumnsAreTheFourFixedOnes() {
        #expect(SlackColumns.all == ["Todo", "In progress", "Blocked", "Done"])
        #expect(SlackColumns.done == "Done")
    }

    @Test(arguments: [("Inprogress", "In progress"), ("in-progress", "In progress"), ("IN PROGRESS", "In progress"), ("in progress", "In progress"),
                      ("DONE", "Done"), ("todo", "Todo"), (" Blocked ", "Blocked")])
    func canonicalMapsSpellingVariants(status: String, expected: String) {
        #expect(SlackColumns.canonical(status) == expected)
    }

    @Test(arguments: ["weird", "", "Open"])
    func canonicalReturnsNilForAnythingElse(status: String) {
        #expect(SlackColumns.canonical(status) == nil)
    }

    @Test func aBoardGroupsCardsByTheFourColumnsInOrder() {
        let groups = SlackBoard.groups([task("1.1", status: "Done"), task("2.2", status: "Todo")], for: tag())
        #expect(groups.map(\.name) == SlackColumns.all)
        #expect(groups[0].tasks.map(\.threadTS) == ["2.2"])
        #expect(groups[3].tasks.map(\.threadTS) == ["1.1"])
    }

    @Test func aCardWithAnUnknownStatusShowsInTodo() {
        let groups = SlackBoard.groups([task("1.1", status: "Gone")], for: tag())
        #expect(groups[0].tasks.map(\.threadTS) == ["1.1"])
        #expect(groups[1].tasks.isEmpty)
    }

    @Test func archivedCardsAndOtherTagsAreLeftOut() {
        let groups = SlackBoard.groups([task("1.1", status: "Todo", archived: true), task("2.2", tag: "other", status: "Todo")], for: tag())
        #expect(groups.allSatisfy { $0.tasks.isEmpty })
    }

    @Test func cardsAreNewestActivityFirst() {
        let old = Date(timeIntervalSince1970: 1_794_000_000)
        let groups = SlackBoard.groups([task("1.1", status: "Todo", lastReply: old), task("2.2", status: "Todo", lastReply: old + 100)], for: tag())
        #expect(groups[0].tasks.map(\.threadTS) == ["2.2", "1.1"])
    }

    @Test func aListIsOneGroupOfAllActiveCards() {
        let groups = SlackBoard.groups([task("1.1", status: ""), task("2.2", status: "", archived: true)], for: tag(kind: .list))
        #expect(groups.count == 1)
        #expect(groups[0].name == "")
        #expect(groups[0].tasks.map(\.threadTS) == ["1.1"])
    }

    @Test func sectionsAreBoardTagsSortedByNameIgnoringCase() {
        let tags = [tag("todo", name: "To-do"), tag("saved", name: "Saved", kind: .list), tag("oncall", name: "Ticket Oncall"), tag("a", name: "alpha")]
        let sections = SlackBoard.sections([], tags: tags)
        #expect(sections.map(\.tag.id) == ["a", "oncall", "todo"])
        #expect(sections.allSatisfy { $0.columns.map(\.name) == SlackColumns.all })
    }

    @Test func eachSectionHoldsOnlyItsOwnTagsCards() {
        let tags = [tag("a", name: "A"), tag("b", name: "B")]
        let sections = SlackBoard.sections([task("1.1", tag: "a", status: "Blocked"), task("2.2", tag: "b", status: "Done"), task("3.3", tag: "b", status: "Weird"),
                                            task("4.4", tag: "b", status: "Todo", archived: true)], tags: tags)
        #expect(sections[0].columns[2].tasks.map(\.threadTS) == ["1.1"])
        #expect(sections[1].columns[3].tasks.map(\.threadTS) == ["2.2"])
        #expect(sections[1].columns[0].tasks.map(\.threadTS) == ["3.3"])
        #expect(sections[1].columns[0].tasks.count == 1)
    }

    @Test func mergedHasFourColumnsWithEveryBoardTagsCardsNewestFirst() {
        let old = Date(timeIntervalSince1970: 1_794_000_000)
        let tags = [tag("a"), tag("b"), tag("saved", kind: .list)]
        let tasks = [task("1.1", tag: "a", status: "Todo", lastReply: old), task("2.2", tag: "b", status: "Todo", lastReply: old + 50),
                     task("3.3", tag: "saved", status: ""), task("4.4", tag: "a", status: "Done")]
        let merged = SlackBoard.merged(tasks, tags: tags)
        #expect(merged.map(\.name) == SlackColumns.all)
        #expect(merged[0].tasks.map(\.threadTS) == ["2.2", "1.1"])
        #expect(merged[3].tasks.map(\.threadTS) == ["4.4"])
        #expect(merged.flatMap(\.tasks).count == 3)
    }
}
