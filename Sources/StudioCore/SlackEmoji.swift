import Foundation

/// Turns Slack emoji names into glyphs for the common standard emoji; custom names have none.
public enum SlackEmoji {
    private static let glyphs: [String: String] = [
        "ticket": "🎫", "white_check_mark": "✅", "heavy_check_mark": "✔️", "x": "❌", "eyes": "👀", "+1": "👍", "thumbsup": "👍", "-1": "👎",
        "thumbsdown": "👎", "fire": "🔥", "rocket": "🚀", "bug": "🐛", "memo": "📝", "pushpin": "📌", "round_pushpin": "📍", "star": "⭐",
        "bookmark": "🔖", "hourglass": "⌛", "hourglass_flowing_sand": "⏳", "warning": "⚠️", "rotating_light": "🚨", "sos": "🆘",
        "raised_hands": "🙌", "pray": "🙏", "tada": "🎉", "bulb": "💡", "wrench": "🔧", "hammer_and_wrench": "🛠️", "mag": "🔍",
        "speech_balloon": "💬", "thought_balloon": "💭", "calendar": "📆", "date": "📅", "bell": "🔔", "zap": "⚡", "question": "❓",
        "exclamation": "❗", "heavy_exclamation_mark": "❗", "red_circle": "🔴", "large_green_circle": "🟢", "large_blue_circle": "🔵",
        "large_yellow_circle": "🟡", "large_orange_circle": "🟠", "tickets": "🎟️", "clipboard": "📋", "link": "🔗", "package": "📦",
        "lock": "🔒", "key": "🔑", "money_with_wings": "💸", "moneybag": "💰", "construction": "🚧", "no_entry": "⛔", "stop_sign": "🛑",
        "100": "💯", "heart": "❤️", "smile": "😄", "thinking_face": "🤔", "point_up": "☝️", "point_right": "👉", "ok_hand": "👌",
        "white_circle": "⚪", "black_circle": "⚫", "checkered_flag": "🏁", "alarm_clock": "⏰", "stopwatch": "⏱️", "inbox_tray": "📥",
        "outbox_tray": "📤", "email": "📧", "phone": "☎️", "mega": "📣", "loudspeaker": "📢", "books": "📚", "book": "📖",
    ]

    /// The emoji for a name (colons and a `::skin-tone-N` suffix ignored), or nil for custom or unknown names.
    public static func glyph(for name: String) -> String? {
        let base = name.components(separatedBy: "::")[0].lowercased()
        return glyphs[base]
    }

    /// The glyph, or `:name:` when there is none.
    public static func label(for name: String) -> String {
        glyph(for: name) ?? ":\(name):"
    }
}
