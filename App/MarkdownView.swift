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
        let markedURL = Bundle.main.url(forResource: "marked.min", withExtension: "js")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Resources/marked.min.js")
        let marked = (try? String(contentsOf: markedURL, encoding: .utf8)) ?? ""
        return """
        <!doctype html><html data-theme="\(theme.rawValue)"><head><meta charset="utf-8"><base href="\(baseHref)">
        <style>\(css)</style><script>\(marked)</script></head>
        <body><article id="c"></article>
        <div id="ov" hidden><button id="ovx" title="Close (Esc)">✕</button><div id="ovb"></div></div>
        <script>
        const esc = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
        marked.use({ renderer: { html(h) { return esc(typeof h === 'string' ? h : h.text); } } });
        const ov = document.getElementById('ov'), ovb = document.getElementById('ovb');
        let current = null, expanded = -1, scale = 1;
        function sizeSvg() {
          const svg = ovb.querySelector('svg'), box = svg && svg.viewBox.baseVal;
          if (!box || !box.width) return null;
          svg.style.width = box.width * scale + 'px';
          svg.style.height = box.height * scale + 'px';
          return svg;
        }
        function expand(i) {
          const d = current && current.diagrams[i];
          if (!d || !d.svg) { collapse(); return; }
          if (i !== expanded) scale = 1;
          ovb.innerHTML = '<div class="ovin">' + d.svg + '</div>';
          ov.hidden = false;
          expanded = i;
          sizeSvg();
        }
        function collapse() { ov.hidden = true; ovb.innerHTML = ''; expanded = -1; }
        window.pinch = function (amount, x, y) {
          const svg = expanded >= 0 && sizeSvg();
          if (!svg) return;
          const r = svg.getBoundingClientRect(), fx = (x - r.left) / r.width, fy = (y - r.top) / r.height;
          scale = Math.min(Math.max(scale * (1 + amount), 0.2), 4);
          const n = sizeSvg().getBoundingClientRect();
          ov.scrollLeft += n.left + fx * n.width - x;
          ov.scrollTop += n.top + fy * n.height - y;
        };
        document.addEventListener('click', e => {
          const b = e.target.closest('.expand');
          if (b) expand(+b.dataset.i);
          else if (e.target.closest('#ovx')) collapse();
        });
        document.addEventListener('keydown', e => { if (e.key === 'Escape' && expanded >= 0) collapse(); });
        window.renderDoc = function (doc) {
          current = doc;
          let html = marked.parse(doc.markdown);
          doc.diagrams.forEach((d, i) => {
            const token = '@@PLANTUML-STUDIO-DIAGRAM-' + i + '@@';
            const box = d.svg ? '<div class="diagram"><button class="expand" data-i="' + i + '" title="Expand diagram">⤢</button>' + d.svg + '</div>'
              : d.error ? '<pre class="error">' + esc(d.error) + '</pre>'
              : '<p class="pending">Rendering diagram…</p>';
            html = html.split('<p>' + token + '</p>').join(box).split(token).join(box);
          });
          document.getElementById('c').innerHTML = html;
          if (expanded >= 0) expand(expanded);
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
    .diagram { position:relative; text-align:center; background:var(--diagram-bg); border:1px solid var(--line); border-radius:6px; padding:12px; margin:1em 0; overflow:auto; }
    .diagram svg { max-width:100%; height:auto !important; }
    .expand, #ovx { width:28px; height:28px; border:1px solid var(--line); border-radius:6px; background:var(--bg); color:var(--fg); font-size:15px; line-height:1; cursor:pointer; }
    .expand { position:absolute; top:8px; right:8px; opacity:0; }
    .diagram:hover .expand, .expand:focus-visible { opacity:1; }
    #ov { position:fixed; inset:0; z-index:10; display:flex; overflow:auto; background:var(--bg); }
    #ov[hidden] { display:none; }
    #ovx { position:fixed; top:10px; right:14px; z-index:11; }
    .ovin { margin:auto; padding:48px 24px 24px; }
    .ovin svg { display:block; border-radius:6px; }
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
