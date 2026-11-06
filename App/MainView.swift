import SwiftUI
import StudioCore

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        content
            .navigationTitle(model.inPlayground ? (isMarkdown ? "Markdown Playground" : "PlantUML Playground") : session.url.lastPathComponent + (session.isDirty ? " •" : ""))
            .onChange(of: model.mode) { _, _ in model.scheduleRender(debounce: false) }
    }

    private var isMarkdown: Bool { DocumentKind(url: session.url) == .markdown }

    @ViewBuilder private var content: some View {
        switch model.mode {
        case .view:
            if isMarkdown { MarkdownPane(url: session.url) } else { DiagramPane() }
        case .edit:
            CodeEditor(text: $session.text, highlightsPlantUML: !isMarkdown)
        case .editPreview:
            if isMarkdown { MarkdownEditPreview(session: session) } else { PlaygroundView(session: session) }
        }
    }
}
