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

    private static let script = AppResources.text("diagram-context.js")

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
