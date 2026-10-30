import SwiftUI
import WebKit

struct SVGView: NSViewRepresentable {
    let svg: Data

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.last != svg else { return }
        context.coordinator.last = svg
        let body = String(decoding: svg, as: UTF8.self)
        let html = """
        <html><body style="margin:0;padding:16px;box-sizing:border-box;min-height:100vh;display:flex;background:#fff">
        <div style="margin:auto">\(body)</div>
        </body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator { var last: Data? }
}
