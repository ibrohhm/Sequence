import SwiftUI
import StudioCore

struct MarkdownPane: View {
    @EnvironmentObject var model: AppModel
    let url: URL

    var body: some View {
        MarkdownView(preview: model.markdownPreview, baseDirectory: url.deletingLastPathComponent(), theme: model.theme)
    }
}

struct MarkdownEditPreview: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        HSplitView {
            CodeEditor(text: $session.text, highlightsPlantUML: false).frame(minWidth: 280)
            MarkdownPane(url: session.url).frame(minWidth: 280)
        }
        .onChange(of: session.text) { _, _ in model.scheduleRender(debounce: true) }
    }
}
