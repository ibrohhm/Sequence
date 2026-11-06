import Foundation

public enum MarkdownFormat {
    case bold, italic

    var marker: String { self == .bold ? "**" : "*" }

    fileprivate func isPresent(inRun run: Int) -> Bool { self == .bold ? run >= 2 : run % 2 == 1 }
}

/// A text change: replace `range` with `replacement`, then select `selection` (in the new text).
public struct TextEdit: Equatable {
    public let range: NSRange
    public let replacement: String
    public let selection: NSRange
}

public enum MarkdownFormatter {
    /// Wraps the selection in bold or italic markers, or removes them when already applied.
    public static func toggle(_ format: MarkdownFormat, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let marker = format.marker
        let width = marker.utf16.count
        let trimmed = trimmedRange(selection, in: ns)
        guard trimmed.length > 0 else {
            let caret = selection.location
            return TextEdit(range: NSRange(location: caret, length: 0), replacement: marker + marker, selection: NSRange(location: caret + width, length: 0))
        }
        let inner = ns.substring(with: trimmed) as NSString

        let leading = run(in: inner, from: 0, step: 1)
        let trailing = run(in: inner, from: inner.length - 1, step: -1)
        if leading + trailing < inner.length, format.isPresent(inRun: min(leading, trailing)) {
            let body = inner.substring(with: NSRange(location: width, length: inner.length - 2 * width))
            return TextEdit(range: trimmed, replacement: body, selection: NSRange(location: trimmed.location, length: (body as NSString).length))
        }

        let before = run(in: ns, from: trimmed.location - 1, step: -1)
        let after = run(in: ns, from: trimmed.location + trimmed.length, step: 1)
        if format.isPresent(inRun: min(before, after)) {
            return TextEdit(range: NSRange(location: trimmed.location - width, length: trimmed.length + 2 * width),
                            replacement: inner as String,
                            selection: NSRange(location: trimmed.location - width, length: trimmed.length))
        }

        return TextEdit(range: trimmed, replacement: marker + (inner as String) + marker,
                        selection: NSRange(location: trimmed.location + width, length: trimmed.length))
    }

    private static func run(in text: NSString, from start: Int, step: Int) -> Int {
        var count = 0
        var index = start
        while index >= 0, index < text.length, text.character(at: index) == 0x2A {
            count += 1
            index += step
        }
        return count
    }

    private static func trimmedRange(_ range: NSRange, in text: NSString) -> NSRange {
        func isSpace(_ index: Int) -> Bool {
            Unicode.Scalar(text.character(at: index)).map { CharacterSet.whitespacesAndNewlines.contains($0) } ?? false
        }
        var start = range.location
        var end = range.location + range.length
        while start < end, isSpace(start) { start += 1 }
        while end > start, isSpace(end - 1) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }
}
