import SwiftUI
import WebKit
import StudioCore

/// Shows one React Flow graph in an editable web view and reports the edited graph.
struct FlowWebView: NSViewRepresentable {
    let flowID: Int?
    let graph: String?
    let theme: Theme
    let onChanged: (Int, String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "flow")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.view = view
        let page = AppResources.url("flow.html")
        view.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onChanged = onChanged
        coordinator.state = (flowID, graph, theme)
        coordinator.push()
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "flow")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler {
        weak var view: WKWebView?
        var onChanged: (Int, String) -> Void = { _, _ in }
        var state: (id: Int?, graph: String?, theme: Theme) = (nil, nil, .light)
        private var ready = false
        private var sent: (id: Int?, graph: String?)?
        private var sentTheme: Theme?

        func push() {
            guard ready, let view else { return }
            if sentTheme != state.theme {
                sentTheme = state.theme
                view.evaluateJavaScript("window.sequenceFlow.theme('\(state.theme.rawValue)')")
            }
            guard sent?.id != state.id || sent?.graph != state.graph else { return }
            sent = (state.id, state.graph)
            let payload = "{\"flowId\":\(state.id.map(String.init) ?? "null"),\"graph\":\(state.graph ?? "null")}"
            view.callAsyncJavaScript("window.sequenceFlow.load(JSON.parse(payload))", arguments: ["payload": payload], in: nil, in: .page) { _ in }
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            if type == "ready" {
                ready = true
                sent = nil
                sentTheme = nil
                push()
            } else if type == "changed", let flowID = body["flowId"] as? Int, let graph = body["graph"] as? String {
                onChanged(flowID, graph)
            }
        }
    }
}
