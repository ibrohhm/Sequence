import Testing
import Foundation
@testable import StudioCore

private func apply(_ edit: TextEdit, to text: String) -> String {
    (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
}

private func range(of word: String, in text: String) -> NSRange { (text as NSString).range(of: word) }

@Suite struct MarkdownFormatterTests {
    private let text = "hello world today"

    @Test func boldWrapsTheSelectionAndKeepsItSelected() {
        let edit = MarkdownFormatter.toggle(.bold, in: text, selection: range(of: "world", in: text))
        let result = apply(edit, to: text)
        #expect(result == "hello **world** today")
        #expect((result as NSString).substring(with: edit.selection) == "world")
    }

    @Test func italicWrapsWithSingleStars() {
        let edit = MarkdownFormatter.toggle(.italic, in: text, selection: range(of: "world", in: text))
        #expect(apply(edit, to: text) == "hello *world* today")
    }

    @Test func boldAgainOnTheInnerWordRemovesTheMarkers() {
        let source = "hello **world** today"
        let edit = MarkdownFormatter.toggle(.bold, in: source, selection: range(of: "world", in: source))
        let result = apply(edit, to: source)
        #expect(result == "hello world today")
        #expect((result as NSString).substring(with: edit.selection) == "world")
    }

    @Test func boldOnASelectionThatIncludesTheMarkersRemovesThem() {
        let source = "hello **world** today"
        let edit = MarkdownFormatter.toggle(.bold, in: source, selection: range(of: "**world**", in: source))
        #expect(apply(edit, to: source) == "hello world today")
    }

    @Test func italicOnBoldTextMakesItBoldItalic() {
        let source = "hello **world** today"
        let edit = MarkdownFormatter.toggle(.italic, in: source, selection: range(of: "world", in: source))
        #expect(apply(edit, to: source) == "hello ***world*** today")
    }

    @Test func boldOnItalicTextMakesItBoldItalic() {
        let source = "hello *world* today"
        let edit = MarkdownFormatter.toggle(.bold, in: source, selection: range(of: "world", in: source))
        #expect(apply(edit, to: source) == "hello ***world*** today")
    }

    @Test func italicOnBoldItalicTextLeavesBold() {
        let source = "hello ***world*** today"
        let edit = MarkdownFormatter.toggle(.italic, in: source, selection: range(of: "world", in: source))
        #expect(apply(edit, to: source) == "hello **world** today")
    }

    @Test func boldOnBoldItalicTextLeavesItalic() {
        let source = "hello ***world*** today"
        let edit = MarkdownFormatter.toggle(.bold, in: source, selection: range(of: "world", in: source))
        #expect(apply(edit, to: source) == "hello *world* today")
    }

    @Test func emptySelectionInsertsAPairWithTheCaretBetween() {
        let edit = MarkdownFormatter.toggle(.bold, in: text, selection: NSRange(location: 6, length: 0))
        #expect(apply(edit, to: text) == "hello ****world today")
        #expect(edit.selection == NSRange(location: 8, length: 0))
    }

    @Test func spacesAtTheSelectionEdgesStayOutsideTheMarkers() {
        let edit = MarkdownFormatter.toggle(.bold, in: text, selection: range(of: " world ", in: text))
        #expect(apply(edit, to: text) == "hello **world** today")
    }

    @Test func multibyteTextIsWrappedByUTF16Offsets() {
        let source = "naïve 😀 café"
        let edit = MarkdownFormatter.toggle(.italic, in: source, selection: range(of: "😀", in: source))
        #expect(apply(edit, to: source) == "naïve *😀* café")
    }
}
