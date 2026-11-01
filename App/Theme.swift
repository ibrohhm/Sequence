import SwiftUI
import AppKit

/// The two app themes. Dark follows VS Code's "Dark Modern" palette.
enum Theme: String {
    case light, dark

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
    var toggled: Theme { self == .dark ? .light : .dark }

    var editorBackground: NSColor { self == .dark ? NSColor(hex: 0x1F1F1F) : .textBackgroundColor }
    var editorText: NSColor { self == .dark ? NSColor(hex: 0xCCCCCC) : .textColor }
    var caret: NSColor { self == .dark ? NSColor(hex: 0xAEAFAD) : .textColor }
    var directive: NSColor { self == .dark ? NSColor(hex: 0xC586C0) : .systemPurple }
    var comment: NSColor { self == .dark ? NSColor(hex: 0x6A9955) : .systemGray }
    var arrow: NSColor { self == .dark ? NSColor(hex: 0x569CD6) : .systemOrange }

    var selectedRow: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x04395E)) : Color.primary.opacity(0.16) }
    var hoverRow: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x2A2D2E)) : Color.primary.opacity(0.08) }

    static let cssVariables = """
    :root, :root[data-theme="light"] { color-scheme: light; --fg:#1f2328; --bg:#fff; --muted:#59636e; --line:#d1d9e0; --code:#f6f8fa; --link:#0969da; --diagram-bg:#fff; }
    :root[data-theme="dark"] { color-scheme: dark; --fg:#cccccc; --bg:#1f1f1f; --muted:#9d9d9d; --line:#3c3c3c; --code:#2b2b2b; --link:#4daafc; --diagram-bg:#fff; }
    """
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
