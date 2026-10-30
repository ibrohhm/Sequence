import SwiftUI
import AppKit

struct CodeEditor: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.allowsUndo = true
        textView.delegate = context.coordinator
        textView.string = text
        Coordinator.highlight(textView)
        scroll.verticalRulerView = LineNumberRuler(textView: textView)
        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let textView = scroll.documentView as! NSTextView
        context.coordinator.parent = self
        if textView.string != text {
            textView.string = text
            Coordinator.highlight(textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            Self.highlight(textView)
        }

        static func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let full = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes([.font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular), .foregroundColor: NSColor.textColor], range: full)
            let rules: [(String, NSColor)] = [
                ("^\\s*@(start|end)\\w*.*$", .systemPurple),
                ("^\\s*'.*$", .systemGray),
                ("[<>o]?[-.]+[>\\\\/]+|<[-.]+", .systemOrange),
            ]
            for (pattern, color) in rules {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) else { continue }
                for match in regex.matches(in: storage.string, range: full) {
                    storage.addAttribute(.foregroundColor, value: color, range: match.range)
                }
            }
            storage.endEditing()
        }
    }
}

final class LineNumberRuler: NSRulerView {
    private weak var textView: NSTextView?

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSView.boundsDidChangeNotification, object: textView.enclosingScrollView?.contentView)
        textView.enclosingScrollView?.contentView.postsBoundsChangedNotifications = true
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func refresh() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        let visible = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let string = textView.string as NSString
        var line = string.substring(to: layout.characterIndexForGlyph(at: visible.location)).components(separatedBy: "\n").count
        var index = visible.location
        while index < NSMaxRange(visible) {
            let charIndex = layout.characterIndexForGlyph(at: index)
            let lineRange = string.lineRange(for: NSRange(location: charIndex, length: 0))
            let glyphRange = layout.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let rect = layout.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            let y = rect.minY + textView.textContainerOrigin.y - textView.visibleRect.minY
            let label = "\(line)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: y), withAttributes: attrs)
            index = NSMaxRange(glyphRange)
            line += 1
        }
    }
}
