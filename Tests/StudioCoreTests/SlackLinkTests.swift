import Testing
@testable import StudioCore

@Suite struct SlackLinkTests {
    @Test func parsesARootMessageLink() throws {
        let link = try #require(SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929"))
        #expect(link.host == "amartha.slack.com")
        #expect(link.channelID == "C07R08WFC81")
        #expect(link.ts == "1794536057.965929")
        #expect(link.threadTS == nil)
        #expect(link.rootTS == "1794536057.965929")
        #expect(link.permalink == "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929")
    }

    @Test func aReplyLinkKeysToTheThreadRoot() throws {
        let link = try #require(SlackLink.parse("https://amartha.slack.com/archives/C07R08WFC81/p1794540000000100?thread_ts=1794536057.965929&cid=C07R08WFC81"))
        #expect(link.ts == "1794540000.000100")
        #expect(link.threadTS == "1794536057.965929")
        #expect(link.rootTS == "1794536057.965929")
        #expect(link.permalink == "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929")
    }

    @Test func trimsWhitespaceAndNewlines() {
        #expect(SlackLink.parse("  \n https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929 \n") != nil)
    }

    @Test(arguments: [
        "hello",
        "https://example.com/archives/C07R08WFC81/p1794536057965929",
        "https://amartha.slack.com/archives/C07R08WFC81/1794536057965929",
        "https://amartha.slack.com/archives/C07R08WFC81/p12345",
        "https://amartha.slack.com/archives/C07R08WFC81/p1794536057965929?thread_ts=junk",
        "https://amartha.slack.com/archives/c07-r/p1794536057965929",
    ])
    func rejectsWhatIsNotAMessageLink(text: String) {
        #expect(SlackLink.parse(text) == nil)
    }
}
