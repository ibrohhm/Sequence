import AppKit
import WebKit
import Combine

/// A web view whose right-click menu holds only Copy Image, and only when the click lands on a diagram.
final class DiagramWebView: WKWebView {
    private var hitRect: CGRect?
    var zoomsOnPinch = false
    private var finds: AnyCancellable?

    func listen(to requests: PassthroughSubject<FindRequest, Never>) {
        finds = requests.sink { [weak self] request in
            let configuration = WKFindConfiguration()
            configuration.backwards = request.backwards
            configuration.caseSensitive = false
            configuration.wraps = true
            self?.find(request.query, configuration: configuration) { _ in }
        }
    }

    override func magnify(with event: NSEvent) {
        guard zoomsOnPinch else { return super.magnify(with: event) }
        pageZoom = min(max(pageZoom * (1 + event.magnification), 0.2), 4)
    }

    static func make() -> DiagramWebView {
        let router = Router()
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(router, name: "diagramContext")
        configuration.userContentController.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        let view = DiagramWebView(frame: .zero, configuration: configuration)
        router.view = view
        return view
    }

    private static let script = """
    document.addEventListener('contextmenu', function (e) {
      var s = e.target && e.target.closest ? e.target.closest('svg') : null;
      var msg = {};
      if (s) { var r = s.getBoundingClientRect(); msg = { x: r.x, y: r.y, width: r.width, height: r.height }; }
      window.webkit.messageHandlers.diagramContext.postMessage(msg);
    }, true);
    """

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.removeAllItems()
        guard hitRect != nil else { return }
        let copyImage = NSMenuItem(title: "Copy Image", action: #selector(copyImage), keyEquivalent: "")
        copyImage.target = self
        menu.addItem(copyImage)
    }

    @objc private func copyImage() {
        guard let hitRect else { return }
        let configuration = WKSnapshotConfiguration()
        configuration.rect = hitRect
        configuration.afterScreenUpdates = true
        takeSnapshot(with: configuration) { image, _ in
            guard let image else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    fileprivate func setHit(_ body: Any) {
        guard let d = body as? [String: Any],
              let x = d["x"] as? Double, let y = d["y"] as? Double, let w = d["width"] as? Double, let h = d["height"] as? Double
        else { hitRect = nil; return }
        hitRect = CGRect(x: x, y: y, width: w, height: h)
    }

    private final class Router: NSObject, WKScriptMessageHandler {
        weak var view: DiagramWebView?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { view?.setHit(message.body) }
    }
}
