import SwiftUI
import WebKit
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

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let view = DiagramWebView.make()
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
        let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/marked.min.js")
        let marked = (try? String(contentsOf: markedURL, encoding: .utf8)) ?? ""
        return """
        <!doctype html><html data-theme="\(theme.rawValue)"><head><meta charset="utf-8"><base href="\(baseHref)">
        <style>\(css)</style><script>\(marked)</script></head>
        <body><article id="c"></article>
        <script>
        const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        marked.use({ renderer: { html(h) { return esc(typeof h === 'string' ? h : h.text); } } });
        window.renderDoc = function (doc) {
          let html = marked.parse(doc.markdown);
          doc.diagrams.forEach((d, i) => {
            const token = '@@PLANTUML-STUDIO-DIAGRAM-' + i + '@@';
            const box = d.svg ? '<div class="diagram">' + d.svg + '</div>'
              : d.error ? '<pre class="error">' + esc(d.error) + '</pre>'
              : '<p class="pending">Rendering diagram…</p>';
            html = html.split('<p>' + token + '</p>').join(box).split(token).join(box);
          });
          document.getElementById('c').innerHTML = html;
        };
        </script></body></html>
        """
    }

    private static let css = Theme.cssVariables + """
    body { margin:0; background:var(--bg); color:var(--fg); font:15px/1.6 -apple-system, BlinkMacSystemFont, sans-serif; }
    article { max-width:860px; margin:0 auto; padding:24px 32px 64px; }
    h1,h2 { padding-bottom:.3em; border-bottom:1px solid var(--line); }
    h1,h2,h3,h4 { margin:1.4em 0 .6em; line-height:1.25; }
    a { color:var(--link); }
    code { font:13px ui-monospace, SFMono-Regular, Menlo, monospace; background:var(--code); padding:.15em .35em; border-radius:4px; }
    pre { background:var(--code); padding:14px 16px; border-radius:6px; overflow:auto; }
    pre code { background:none; padding:0; }
    blockquote { margin:0; padding:0 1em; color:var(--muted); border-left:4px solid var(--line); }
    table { border-collapse:collapse; display:block; overflow:auto; }
    th,td { border:1px solid var(--line); padding:6px 13px; }
    tr:nth-child(2n) { background:var(--code); }
    img { max-width:100%; }
    hr { border:0; border-top:1px solid var(--line); }
    .diagram { text-align:center; background:var(--diagram-bg); border:1px solid var(--line); border-radius:6px; padding:12px; margin:1em 0; overflow:auto; }
    .diagram svg { max-width:100%; height:auto; }
    .error { background:rgba(207,34,46,.12); color:inherit; white-space:pre-wrap; }
    .pending { color:var(--muted); }
    """

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
