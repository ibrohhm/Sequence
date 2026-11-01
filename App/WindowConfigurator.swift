import SwiftUI
import AppKit

/// Keeps window content below the title bar and draws its separator, so resizing or toggling the sidebar never slides content under the toolbar.
struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfigView() }
    func updateNSView(_ view: NSView, context: Context) {}

    private final class ConfigView: NSView {
        override func viewDidMoveToWindow() {
            guard let window else { return }
            window.styleMask.remove(.fullSizeContentView)
            window.titlebarSeparatorStyle = .line
        }
    }
}
