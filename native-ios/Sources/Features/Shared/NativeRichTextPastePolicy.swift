import Foundation

enum NativeRichTextPastePolicy {
    static let maximumParagraphSpacing: CGFloat = 4

    static func compactParagraphSpacing(in source: NSAttributedString) -> NSAttributedString {
        guard source.length > 0 else { return source.copy() as? NSAttributedString ?? source }
        let result = NSMutableAttributedString(attributedString: source)
        let fullRange = NSRange(location: 0, length: result.length)
        var updates: [(NSRange, NSParagraphStyle)] = []
        result.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            guard let style = value as? NSParagraphStyle,
                  style.paragraphSpacing > maximumParagraphSpacing || style.paragraphSpacingBefore > maximumParagraphSpacing else { return }
            let compact = (style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            compact.paragraphSpacing = min(max(0, compact.paragraphSpacing), maximumParagraphSpacing)
            compact.paragraphSpacingBefore = min(max(0, compact.paragraphSpacingBefore), maximumParagraphSpacing)
            updates.append((range, compact))
        }
        for (range, style) in updates {
            result.addAttribute(.paragraphStyle, value: style, range: range)
        }
        return result
    }

    static func replace(
        _ replacement: NSAttributedString,
        in range: NSRange,
        of target: NSMutableAttributedString,
        undoManager: UndoManager?,
        onReplacement: ((NSRange, NSAttributedString) -> Void)? = nil
    ) {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= target.length else { return }
        let previous = target.attributedSubstring(from: range)
        undoManager?.registerUndo(withTarget: target) { target in
            replace(
                previous,
                in: NSRange(location: range.location, length: replacement.length),
                of: target,
                undoManager: undoManager,
                onReplacement: onReplacement
            )
        }
        target.replaceCharacters(in: range, with: replacement)
        onReplacement?(range, replacement)
    }
}
