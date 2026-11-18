import SwiftUI
import StudioCore
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

    var frameNSColor: NSColor { self == .dark ? NSColor(hex: 0x141414) : NSColor(hex: 0xEFEFF1) }
    var frameBackground: Color { Color(nsColor: frameNSColor) }
    var panelBackground: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x1F1F1F)) : .white }
    var sidebarBackground: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x181818)) : Color(nsColor: NSColor(hex: 0xFAFAFB)) }
    var selectedRow: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x04395E)) : Color.primary.opacity(0.16) }
    var hoverRow: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x2A2D2E)) : Color.primary.opacity(0.06) }
    var border: Color { self == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.09) }
    var accent: Color { Color(nsColor: NSColor(hex: 0xDB6510)) }

    // Board cards, columns, chips and tabs. Text colours keep 4.5:1 on their fills in both themes.
    var columnBackground: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x181818)) : Color(nsColor: NSColor(hex: 0xF4F4F5)) }
    var cardBackground: Color { self == .dark ? Color(nsColor: NSColor(hex: 0x262626)) : .white }
    var cardBorder: Color { self == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.07) }
    var cardBorderHover: Color { self == .dark ? Color.white.opacity(0.18) : Color.black.opacity(0.16) }
    var cardShadow: Color { self == .dark ? Color.black.opacity(0.35) : Color.black.opacity(0.06) }
    var chipFill: Color { self == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.05) }
    var chipText: Color { self == .dark ? Color(nsColor: NSColor(hex: 0xC8C8C8)) : Color(nsColor: NSColor(hex: 0x4B4B50)) }
    var attentionFill: Color { Color(nsColor: NSColor(hex: 0xDB6510)).opacity(self == .dark ? 0.20 : 0.12) }
    var attentionText: Color { self == .dark ? Color(nsColor: NSColor(hex: 0xF4A868)) : Color(nsColor: NSColor(hex: 0xA64B0A)) }
    /// Jira-style status lozenge colours: Todo neutral, In progress blue, Blocked red, Done green (other statuses count as Todo).
    func statusColors(_ status: String) -> (fill: Color, text: Color) {
        let dark = self == .dark
        func pair(_ fill: UInt32, _ text: UInt32, _ light: UInt32, _ lightText: UInt32) -> (fill: Color, text: Color) {
            (Color(nsColor: NSColor(hex: dark ? fill : light)).opacity(dark ? 0.22 : 0.14), Color(nsColor: NSColor(hex: dark ? text : lightText)))
        }
        switch SlackColumns.canonical(status) {
        case "In progress": return pair(0x4C9AFF, 0x85B8FF, 0x0052CC, 0x0747A6)
        case "Blocked": return pair(0xF87462, 0xFF9C8F, 0xDE350B, 0xA32100)
        case "Done": return pair(0x57D9A3, 0x79F2C0, 0x36B37E, 0x006644)
        default: return (chipFill, chipText)
        }
    }
    var tabTrack: Color { self == .dark ? Color.white.opacity(0.06) : Color.black.opacity(0.05) }

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
