import Foundation

/// A parsed Slack message link, e.g. https://acme.slack.com/archives/C123/p1794536057965929.
public struct SlackLink: Equatable {
    public let host: String
    public let channelID: String
    public let ts: String
    public let threadTS: String?

    public var rootTS: String { threadTS ?? ts }

    /// Link to the thread's first message, without a query string.
    public var permalink: String {
        "https://\(host)/archives/\(channelID)/p\(rootTS.replacingOccurrences(of: ".", with: ""))"
    }

    public static func parse(_ text: String) -> SlackLink? {
        guard let parts = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              parts.scheme == "https", let host = parts.host, host.hasSuffix(".slack.com"), host.count > ".slack.com".count
        else { return nil }
        let path = parts.path.split(separator: "/").map(String.init)
        guard path.count == 3, path[0] == "archives", matches(path[1], "^[A-Z0-9]+$"), matches(path[2], "^p[0-9]{7,}$") else { return nil }
        let digits = String(path[2].dropFirst())
        let ts = String(digits.dropLast(6)) + "." + String(digits.suffix(6))
        var threadTS: String?
        if let item = parts.queryItems?.first(where: { $0.name == "thread_ts" }) {
            guard let value = item.value, matches(value, "^[0-9]+\\.[0-9]+$") else { return nil }
            threadTS = value
        }
        return SlackLink(host: host, channelID: path[1], ts: ts, threadTS: threadTS)
    }

    private static func matches(_ value: String, _ pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
