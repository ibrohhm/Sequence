import SwiftUI
import WebKit
import Combine
import StudioCore

struct MarkdownDiagram: Encodable, Equatable {
    var svg: String?
    var error: String?
}

struct MarkdownPreview: Encodable, Equatable {
    var markdown: String
    var diagrams: [MarkdownDiagram]
}

struct MarkdownView: NSViewRepresentable {
    let preview: MarkdownPreview?
    let baseDirectory: URL
    let theme: Theme
    let finds: PassthroughSubject<FindRequest, Never>

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = DiagramWebView.make()
        view.onPinch = { [weak view] amount, point in
            view?.evaluateJavaScript("window.pinch(\(amount),\(point.x),\(point.y))")
        }
        view.listen(to: finds)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.webView = view
        context.coordinator.theme = theme
        load(view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.apply(theme)
        guard let preview, let data = try? JSONEncoder().encode(preview), let json = String(data: data, encoding: .utf8) else { return }
        context.coordinator.show(json)
    }

    private func load(_ view: WKWebView) {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("sequence-\(UUID().uuidString).html")
        guard (try? Self.page(base: baseDirectory, theme: theme).write(to: file, atomically: true, encoding: .utf8)) != nil else { return }
        view.loadFileURL(file, allowingReadAccessTo: URL(fileURLWithPath: "/"))
    }

    private static func page(base: URL, theme: Theme) -> String {
        let baseHref = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return """
        <!doctype html><html data-theme="\(theme.rawValue)"><head><meta charset="utf-8"><base href="\(baseHref)">
        <style>\(Theme.cssVariables)\(AppResources.text("markdown.css"))</style><script>\(AppResources.text("marked.min.js"))</script></head>
        <body><article id="c"></article>
        <div id="ov" hidden><button id="ovx" title="Close (Esc)">✕</button><div id="ovb"></div></div>
        <script>\(AppResources.text("markdown.js"))</script></body></html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        weak var webView: WKWebView?
        private var loaded = false
        private var latest: String?
        var theme: Theme = .light

        func apply(_ newTheme: Theme) {
            theme = newTheme
            guard loaded else { return }
            webView?.evaluateJavaScript("document.documentElement.dataset.theme='\(newTheme.rawValue)'")
        }

        func show(_ json: String) {
            latest = json
            guard loaded else { return }
            webView?.evaluateJavaScript("window.renderDoc(\(json))")
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            loaded = true
            apply(theme)
            if let latest { webView.evaluateJavaScript("window.renderDoc(\(latest))") }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard action.navigationType == .linkActivated else { decisionHandler(.allow); return }
            if let url = action.request.url, ["http", "https", "mailto"].contains(url.scheme) { NSWorkspace.shared.open(url) }
            decisionHandler(.cancel)
        }
    }
}
