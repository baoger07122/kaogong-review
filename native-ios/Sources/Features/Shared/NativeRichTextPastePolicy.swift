import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum NativeRichTextPastePolicy {
    static let maximumParagraphSpacing: CGFloat = 4

    static func removeOnlyProvenBoundaryNewlines(
        from value: NSMutableAttributedString,
        matching plainText: String
    ) {
        guard value.length > 0,
              !plainText.isEmpty,
              !plainText.hasPrefix("\n"), !plainText.hasPrefix("\r"),
              !plainText.hasSuffix("\n"), !plainText.hasSuffix("\r") else { return }

        var containsAttachment = false
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attribute, _, stop in
            guard attribute != nil else { return }
            containsAttachment = true
            stop.pointee = true
        }
        guard !containsAttachment else { return }

        let richText = value.string
        var leadingLength = 0
        var trailingLength = 0
        for prefix in ["", "\n", "\r\n"] {
            for suffix in ["", "\n", "\r\n"] {
                guard !prefix.isEmpty || !suffix.isEmpty,
                      prefix.utf16.count <= 2,
                      suffix.utf16.count <= 2,
                      richText == prefix + plainText + suffix else { continue }
                leadingLength = prefix.utf16.count
                trailingLength = suffix.utf16.count
                break
            }
            if leadingLength > 0 || trailingLength > 0 { break }
        }
        guard leadingLength > 0 || trailingLength > 0 else { return }
        if trailingLength > 0 {
            value.deleteCharacters(in: NSRange(location: value.length - trailingLength, length: trailingLength))
        }
        if leadingLength > 0 {
            value.deleteCharacters(in: NSRange(location: 0, length: leadingLength))
        }
    }

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
