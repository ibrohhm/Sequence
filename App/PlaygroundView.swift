import SwiftUI
import StudioCore

struct DiagramPane: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            if let error = model.renderError {
                Text(error)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.red.opacity(0.15))
                    .textSelection(.enabled)
            }
            if let svg = model.lastSVG {
                SVGView(svg: svg, theme: model.theme)
            } else if model.renderError == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }
        }
    }
}

struct PlaygroundView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject var session: DocumentSession

    var body: some View {
        HSplitView {
            CodeEditor(text: $session.text).frame(minWidth: 280)
            DiagramPane().frame(minWidth: 280)
        }
        .onChange(of: session.text) { _, _ in model.scheduleRender(debounce: true) }
    }
}
