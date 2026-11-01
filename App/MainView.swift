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
            .navigationTitle(model.inPlayground ? (isMarkdown ? "Markdown Playground" : "PlantUML Playground") : session.url.lastPathComponent + (session.isDirty ? " •" : ""))
            .toolbar {
                if model.inPlayground {
                    ToolbarItem(placement: .navigation) {
                        Button { model.closePlayground() } label: { Label("Back to files", systemImage: "chevron.left") }
                            .help("Close playground and go back")
                    }
                    ToolbarItem { Button("Save to folder…") { model.saveCopyOfPlayground() } }
                } else {
                    ToolbarItem { modePicker }
                    ToolbarItem { Button("Save") { model.save() }.disabled(!session.isDirty) }
                }
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
            Label("View", systemImage: "eye").labelStyle(.iconOnly).help("View").tag(ViewMode.view)
            Label("Edit", systemImage: "pencil").labelStyle(.iconOnly).help("Edit").tag(ViewMode.edit)
            Label("Edit with preview", systemImage: "rectangle.split.2x1").labelStyle(.iconOnly).help("Edit with preview").tag(ViewMode.editPreview)
        }
        .pickerStyle(.segmented)
    }
}
