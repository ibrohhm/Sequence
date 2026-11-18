import Testing
@testable import StudioCore

@Suite struct SlackEmojiTests {
    @Test func knownNamesBecomeTheEmoji() {
        #expect(SlackEmoji.glyph(for: "ticket") == "🎫")
        #expect(SlackEmoji.glyph(for: "white_check_mark") == "✅")
        #expect(SlackEmoji.glyph(for: "+1") == "👍")
    }

    @Test func aSkinToneSuffixIsIgnoredAndCaseDoesNotMatter() {
        #expect(SlackEmoji.glyph(for: "+1::skin-tone-3") == "👍")
        #expect(SlackEmoji.glyph(for: "Ticket") == "🎫")
    }

    @Test func customOrUnknownNamesHaveNoGlyph() {
        #expect(SlackEmoji.glyph(for: "loading") == nil)
        #expect(SlackEmoji.glyph(for: "") == nil)
    }

    @Test func labelShowsTheGlyphOrTheColonName() {
        #expect(SlackEmoji.label(for: "ticket") == "🎫")
        #expect(SlackEmoji.label(for: "loading") == ":loading:")
    }
}
