import Foundation
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

enum NativeRichTextPastePolicy {
    static let maximumParagraphSpacing: CGFloat = 4
    static let explicitParagraphSpacing = NSAttributedString.Key("NativeRichTextPasteExplicitParagraphSpacing")
    static let semanticHeadingParagraph = NSAttributedString.Key("NativeRichTextPasteSemanticHeading")
    static let confirmedNaturalParagraph = NSAttributedString.Key("NativeRichTextPasteConfirmedNaturalParagraph")

    static func removeOnlyProvenBoundaryNewlines(
        from value: NSMutableAttributedString,
        matching plainText: String
    ) {
        guard value.length > 0, !plainText.isEmpty else { return }

        var attachmentRanges: [NSRange] = []
        value.enumerateAttribute(.attachment, in: NSRange(location: 0, length: value.length)) { attribute, range, _ in
            guard attribute != nil else { return }
            attachmentRanges.append(range)
        }

        let richText = value.string
        let normalizedPlainText = richTextNormalizingLineEndings(plainText)
        let normalizedRichText = richTextNormalizingLineEndings(richText)
        guard !normalizedPlainText.hasPrefix("\n"), !normalizedPlainText.hasSuffix("\n") else { return }
        var leadingLength = 0
        var trailingLength = 0
        for hasLeadingBoundary in [false, true] {
            for hasTrailingBoundary in [false, true] {
                let prefix = hasLeadingBoundary ? "\n" : ""
                let suffix = hasTrailingBoundary ? "\n" : ""
                guard !prefix.isEmpty || !suffix.isEmpty,
                      normalizedRichText == prefix + normalizedPlainText + suffix else { continue }
                leadingLength = hasLeadingBoundary ? (richText.hasPrefix("\r\n") ? 2 : 1) : 0
                trailingLength = hasTrailingBoundary ? (richText.hasSuffix("\r\n") ? 2 : 1) : 0
                break
            }
            if leadingLength > 0 || trailingLength > 0 { break }
        }
        guard leadingLength > 0 || trailingLength > 0 else { return }
        let boundaryRanges = [
            leadingLength > 0 ? NSRange(location: 0, length: leadingLength) : nil,
            trailingLength > 0 ? NSRange(location: value.length - trailingLength, length: trailingLength) : nil
        ].compactMap { $0 }
        guard !attachmentRanges.contains(where: { attachment in
            boundaryRanges.contains { NSIntersectionRange(attachment, $0).length > 0 }
        }) else { return }
        if trailingLength > 0 {
            value.deleteCharacters(in: NSRange(location: value.length - trailingLength, length: trailingLength))
        }
        if leadingLength > 0 {
            value.deleteCharacters(in: NSRange(location: 0, length: leadingLength))
        }
    }

    private static func richTextNormalizingLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
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

        let text = result.string as NSString
        var paragraphs: [(range: NSRange, contentRange: NSRange, style: NSParagraphStyle)] = []
        var cursor = 0
        while cursor < text.length {
            var start = 0
            var end = 0
            var contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: cursor, length: 0))
            guard end > cursor else { break }
            let range = NSRange(location: start, length: min(end - start, result.length - start))
            let contentRange = NSRange(location: start, length: max(0, min(contentsEnd, result.length) - start))
            let style = range.location < result.length
                ? (result.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle ?? .default)
                : .default
            paragraphs.append((range, contentRange, style))
            cursor = end
        }
        guard paragraphs.count > 1 else { return result.copy() as? NSAttributedString ?? result }

        func hasContent(_ range: NSRange) -> Bool {
            guard range.length > 0 else { return false }
            return !text.substring(with: range).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        func isSpecial(_ paragraph: (range: NSRange, contentRange: NSRange, style: NSParagraphStyle)) -> Bool {
            guard hasContent(paragraph.contentRange) else { return true }
            if paragraph.style.headIndent > 0.5 || paragraph.style.firstLineHeadIndent > 0.5 { return true }
            if result.attribute(semanticHeadingParagraph, at: paragraph.range.location, effectiveRange: nil) != nil { return true }
            let content = text.substring(with: paragraph.contentRange).trimmingCharacters(in: .whitespaces)
            return content.hasPrefix("• ") || content.hasPrefix("◦ ") || content.hasPrefix("▪︎ ")
                || content.hasPrefix("– ") || content.hasPrefix("☐ ") || content.hasPrefix("☑ ")
                || content.range(of: #"^\d+\.\s"#, options: .regularExpression) != nil
        }

        for index in 1..<paragraphs.count {
            let previous = paragraphs[index - 1]
            let current = paragraphs[index]
            guard !isSpecial(previous), !isSpecial(current),
                  result.attribute(confirmedNaturalParagraph, at: previous.range.location, effectiveRange: nil) != nil,
                  result.attribute(confirmedNaturalParagraph, at: current.range.location, effectiveRange: nil) != nil else { continue }
            let sourceGap = max(0, previous.style.paragraphSpacing) + max(0, current.style.paragraphSpacingBefore)
            let hasExplicitSpacing = result.attribute(explicitParagraphSpacing, at: previous.range.location, effectiveRange: nil) != nil
                || result.attribute(explicitParagraphSpacing, at: current.range.location, effectiveRange: nil) != nil
            let gap: CGFloat
            if sourceGap > 0.01 {
                gap = min(sourceGap, maximumParagraphSpacing)
            } else if hasExplicitSpacing {
                gap = 0
            } else {
                gap = maximumParagraphSpacing
            }
            let previousStyle = (previous.style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            previousStyle.paragraphSpacing = gap
            let currentStyle = (current.style.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
            currentStyle.paragraphSpacingBefore = 0
            result.addAttribute(.paragraphStyle, value: previousStyle, range: previous.range)
            result.addAttribute(.paragraphStyle, value: currentStyle, range: current.range)
        }
        return result.copy() as? NSAttributedString ?? result
    }

    @discardableResult
    static func replace(
        _ replacement: NSAttributedString,
        in range: NSRange,
        of target: NSMutableAttributedString,
        undoManager: UndoManager?,
        onReplacement: ((NSRange, NSAttributedString) -> Void)? = nil
    ) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= target.length else { return false }
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
        return true
    }
}
