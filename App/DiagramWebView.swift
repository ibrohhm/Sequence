import AppKit
import WebKit
import Combine

/// A web view whose right-click menu holds only Copy Image, and only when the click lands on a diagram.
final class DiagramWebView: WKWebView {
    private var onDiagram = false
    var zoomsOnPinch = false
    /// Receives pinch magnification and the cursor in view points instead of the default handling.
    var onPinch: ((CGFloat, CGPoint) -> Void)?
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
        if let onPinch { return onPinch(event.magnification, convert(event.locationInWindow, from: nil)) }
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
    window.__sequenceSvg = null;
    document.addEventListener('contextmenu', function (e) {
      var s = e.target && e.target.closest ? e.target.closest('svg') : null;
      window.__sequenceSvg = s;
      window.webkit.messageHandlers.diagramContext.postMessage(s ? true : false);
    }, true);
    window.__sequenceCopy = function () {
      var s = window.__sequenceSvg;
      if (!s) return Promise.resolve(null);
      var r = s.getBoundingClientRect();
      var clone = s.cloneNode(true);
      clone.setAttribute('xmlns', 'http://www.w3.org/2000/svg');
      clone.setAttribute('width', r.width);
      clone.setAttribute('height', r.height);
      var url = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(new XMLSerializer().serializeToString(clone));
      return new Promise(function (resolve) {
        var img = new Image();
        img.onload = function () {
          var scale = 2;
          var c = document.createElement('canvas');
          c.width = Math.ceil(r.width * scale);
          c.height = Math.ceil(r.height * scale);
          var g = c.getContext('2d');
          g.fillStyle = '#fff';
          g.fillRect(0, 0, c.width, c.height);
          g.drawImage(img, 0, 0, c.width, c.height);
          resolve(c.toDataURL('image/png').split(',')[1]);
        };
        img.onerror = function () { resolve(null); };
        img.src = url;
      });
    };
    """

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        super.willOpenMenu(menu, with: event)
        menu.removeAllItems()
        guard onDiagram else { return }
        let copyImage = NSMenuItem(title: "Copy Image", action: #selector(copyImage), keyEquivalent: "")
        copyImage.target = self
        menu.addItem(copyImage)
    }

    @objc private func copyImage() {
        callAsyncJavaScript("return await window.__sequenceCopy();", arguments: [:], in: nil, in: .page) { result in
            guard case .success(let value) = result,
                  let base64 = value as? String,
                  let data = Data(base64Encoded: base64),
                  let image = NSImage(data: data)
            else { return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([image])
        }
    }

    fileprivate func setHit(_ body: Any) {
        onDiagram = (body as? Bool) ?? false
    }

    private final class Router: NSObject, WKScriptMessageHandler {
        weak var view: DiagramWebView?
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) { view?.setHit(message.body) }
    }
}
