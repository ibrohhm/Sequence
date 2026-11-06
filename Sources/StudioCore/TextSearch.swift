import Foundation

public enum TextSearch {
    /// Next case-insensitive match of `query` from `location`, wrapping around the text.
    public static func nextRange(of query: String, in text: String, from location: Int, backwards: Bool = false) -> NSRange? {
        guard !query.isEmpty else { return nil }
        let string = text as NSString
        let split = min(max(location, 0), string.length)
        let options: NSString.CompareOptions = backwards ? [.caseInsensitive, .backwards] : .caseInsensitive
        let before = NSRange(location: 0, length: split)
        let after = NSRange(location: split, length: string.length - split)
        for range in backwards ? [before, after] : [after, before] {
            let found = string.range(of: query, options: options, range: range)
            if found.location != NSNotFound { return found }
        }
        return nil
    }
}
