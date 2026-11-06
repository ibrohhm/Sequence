import Testing
import Foundation
@testable import StudioCore

@Suite struct TextSearchTests {
    private let text = "Alice -> Bob\nbob -> alice\nBOB -> Carol"

    @Test func forwardFindsFirstMatchAtOrAfterLocation() {
        let range = TextSearch.nextRange(of: "bob", in: text, from: 5)
        #expect(range == NSRange(location: 9, length: 3))
    }

    @Test func forwardSkipsMatchesBeforeLocation() {
        let range = TextSearch.nextRange(of: "bob", in: text, from: 10)
        #expect(range == NSRange(location: 13, length: 3))
    }

    @Test func forwardWrapsToTheStart() {
        let range = TextSearch.nextRange(of: "alice", in: text, from: 25)
        #expect(range == NSRange(location: 0, length: 5))
    }

    @Test func backwardFindsLastMatchBeforeLocation() {
        let range = TextSearch.nextRange(of: "bob", in: text, from: 22, backwards: true)
        #expect(range == NSRange(location: 13, length: 3))
    }

    @Test func backwardWrapsToTheEnd() {
        let range = TextSearch.nextRange(of: "bob", in: text, from: 0, backwards: true)
        #expect(range == NSRange(location: 26, length: 3))
    }

    @Test func missingQueryAndEmptyQueryReturnNil() {
        #expect(TextSearch.nextRange(of: "zzz", in: text, from: 0) == nil)
        #expect(TextSearch.nextRange(of: "", in: text, from: 0) == nil)
    }
}
