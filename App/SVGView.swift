import SwiftUI
import WebKit

struct SVGView: NSViewRepresentable {
    let svg: Data
    let theme: Theme

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = DiagramWebView.make()
        view.allowsMagnification = true
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard context.coordinator.last != svg || context.coordinator.lastTheme != theme else { return }
        context.coordinator.last = svg
        context.coordinator.lastTheme = theme
        let body = String(decoding: svg, as: UTF8.self)
        let html = """
        <html data-theme="\(theme.rawValue)"><head><style>\(Theme.cssVariables)</style></head>
        <body style="margin:0;padding:16px;box-sizing:border-box;min-height:100vh;display:flex;background:var(--bg)">
        <div style="margin:auto;background:var(--diagram-bg);border-radius:6px">\(body)</div>
        </body></html>
        """
        view.loadHTMLString(html, baseURL: nil)
    }

    final class Coordinator { var last: Data?; var lastTheme: Theme? }
}
