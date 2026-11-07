import SwiftUI
import AppKit

/// Makes the title bar blend into the window frame color, and keeps content below it so resizing never slides content under it.
struct WindowConfigurator: NSViewRepresentable {
    let theme: Theme

    func makeNSView(context: Context) -> NSView { ConfigView() }

    func updateNSView(_ view: NSView, context: Context) {
        (view as? ConfigView)?.theme = theme
        (view as? ConfigView)?.apply()
    }

    private final class ConfigView: NSView {
        var theme: Theme = .light

        override func viewDidMoveToWindow() { apply() }

        func apply() {
            guard let window else { return }
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .visible
            window.titlebarSeparatorStyle = .none
            window.backgroundColor = theme.frameNSColor
        }
    }
}

/// Calls `onActivate` whenever the hosting window becomes the key window.
struct WindowActivation: NSViewRepresentable {
    let onActivate: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = ActivationView()
        view.onActivate = onActivate
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

private final class ActivationView: NSView {
    var onActivate: () -> Void = {}
    private var token: NSObjectProtocol?

    override func viewDidMoveToWindow() {
        if let token { NotificationCenter.default.removeObserver(token) }
        guard let window else { return }
        token = NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            self?.onActivate()
        }
        if window.isKeyWindow { onActivate() }
    }

    deinit { if let token { NotificationCenter.default.removeObserver(token) } }
}
