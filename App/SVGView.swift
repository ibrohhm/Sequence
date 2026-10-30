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
        view.loadHTMLString("<html><body style=\"margin:16px;background:#fff\">\(body)</body></html>", baseURL: nil)
    }

    final class Coordinator { var last: Data? }
}
