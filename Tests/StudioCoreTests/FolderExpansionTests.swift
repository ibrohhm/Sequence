import Testing
@testable import StudioCore

@Suite struct FolderExpansionTests {
    @Test func unsetFolderUsesTheDefault() {
        let state = FolderExpansion()
        #expect(state.isExpanded("/v/a", default: true))
        #expect(!state.isExpanded("/v/a", default: false))
    }

    @Test func savedChoiceBeatsTheDefault() {
        var state = FolderExpansion()
        state.set("/v/a", expanded: false)
        state.set("/v/b", expanded: true)
        #expect(!state.isExpanded("/v/a", default: true))
        #expect(state.isExpanded("/v/b", default: false))
    }

    @Test func remapMovesSavedChoicesOfAFolderAndItsDescendants() {
        var state = FolderExpansion(states: ["/v/a": true, "/v/a/sub": false, "/v/ab": true])
        state.remap(from: "/v/a", to: "/v/x/a")
        #expect(state.states == ["/v/x/a": true, "/v/x/a/sub": false, "/v/ab": true])
    }
}
