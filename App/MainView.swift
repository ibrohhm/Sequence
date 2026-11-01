import SwiftUI
import StudioCore

struct MainView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Color(nsColor: .separatorColor)).frame(height: 0.5)
            content
        }
            .navigationTitle(session.url.lastPathComponent + (session.isDirty ? " •" : ""))
            .toolbar {
                ToolbarItem { modePicker }
                ToolbarItem { Button("Save") { model.save() }.disabled(!session.isDirty) }
            }
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

    private var modePicker: some View {
        Picker("Mode", selection: $model.mode) {
            Text("View").tag(ViewMode.view)
            Text("Edit").tag(ViewMode.edit)
            Text("Edit with preview").tag(ViewMode.editPreview)
        }
        .pickerStyle(.segmented)
    }
}
