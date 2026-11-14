import Foundation

struct NativeRichTextNoteParagraphHTMLStyle: Equatable, Sendable {
    var spacingBefore: Double
    var spacingAfter: Double
    var lineSpacing: Double
    var fontSize: Double
    var firstLineHeadIndent: Double = 0
    var headIndent: Double = 0
    var tailIndent: Double = 0
}

struct NativeRichTextNoteParagraphHTMLIndent: Equatable, Sendable {
    var firstLineHeadIndent: Double
    var headIndent: Double
    var tailIndent: Double
}

enum NativeRichTextNoteParagraphHTMLPolicy {
    static func removingLegacyInjectedSpacing(
        from styles: [NativeRichTextNoteParagraphHTMLStyle],
        isQuoted: [Bool],
        hasContent: [Bool]
    ) -> [NativeRichTextNoteParagraphHTMLStyle] {
        guard styles.count == isQuoted.count, styles.count == hasContent.count else { return styles }
        let contentIndices = styles.indices.filter { hasContent[$0] }
        let matchesInjectedLineSpacing = contentIndices.count >= 2
            && contentIndices.allSatisfy { approximately(styles[$0].lineSpacing, 2) }
            && contentIndices.contains { !isQuoted[$0] && approximately(styles[$0].spacingAfter, 5) }

        return styles.indices.map { index in
            var style = styles[index]
            if !isQuoted[index], approximately(style.spacingAfter, 5) {
                style.spacingAfter = 0
            }
            if matchesInjectedLineSpacing, hasContent[index], approximately(style.lineSpacing, 2) {
                style.lineSpacing = 0
            }
            return style
        }
    }

    static func applying(_ style: NativeRichTextNoteParagraphHTMLStyle, to html: String) -> String {
        var declarations: [String] = []
        if style.spacingBefore.isFinite, style.spacingBefore > 0.01 {
            declarations.append("margin-top: \(style.spacingBefore)pt")
        }
        if style.spacingAfter.isFinite, style.spacingAfter > 0.01 {
            declarations.append("margin-bottom: \(style.spacingAfter)pt")
        }
        if style.lineSpacing.isFinite, style.lineSpacing > 0.01,
           style.fontSize.isFinite, style.fontSize > 0 {
            declarations.append("line-height: \(style.fontSize + style.lineSpacing)pt")
        }
        let hasIndent = style.firstLineHeadIndent.isFinite
            && style.headIndent.isFinite
            && style.tailIndent.isFinite
            && (abs(style.firstLineHeadIndent) > 0.01 || abs(style.headIndent) > 0.01 || abs(style.tailIndent) > 0.01)
        if hasIndent {
            if abs(style.headIndent) > 0.01 {
                declarations.append("margin-left: \(style.headIndent)pt")
            }
            let firstLineOffset = style.firstLineHeadIndent - style.headIndent
            if abs(firstLineOffset) > 0.01 {
                declarations.append("text-indent: \(firstLineOffset)pt")
            }
            if style.tailIndent < -0.01 {
                declarations.append("margin-right: \(-style.tailIndent)pt")
            }
        }
        guard !declarations.isEmpty || hasIndent,
              let expression = try? NSRegularExpression(pattern: #"(?i)^<(p|h[1-6])\b([^>]*)>"#),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(match.range(at: 1), in: html),
              let fullRange = Range(match.range, in: html) else { return html }
        let tag = String(html[tagRange])
        var attributes: [String] = []
        if !declarations.isEmpty {
            attributes.append("style=\"\(declarations.joined(separator: "; "))\"")
        }
        if hasIndent {
            attributes.append("data-note-first-line-head-indent=\"\(style.firstLineHeadIndent)\"")
            attributes.append("data-note-head-indent=\"\(style.headIndent)\"")
            attributes.append("data-note-tail-indent=\"\(style.tailIndent)\"")
        }
        let replacement = "<\(tag) \(attributes.joined(separator: " "))>"
        return html.replacingCharacters(in: fullRange, with: replacement)
    }

    static func indents(in html: String) -> [NativeRichTextNoteParagraphHTMLIndent?] {
        guard let paragraphExpression = try? NSRegularExpression(pattern: #"(?is)<(?:p|h[1-6])\b([^>]*)>"#),
              let attributeExpression = try? NSRegularExpression(
                pattern: #"(?i)\b(data-note-first-line-head-indent|data-note-head-indent|data-note-tail-indent)\s*=\s*[\"']([^\"']+)[\"']"#
              ) else { return [] }
        let source = html as NSString
        return paragraphExpression.matches(in: html, range: NSRange(location: 0, length: source.length)).map { paragraphMatch in
            guard paragraphMatch.numberOfRanges > 1 else { return nil }
            let attributes = source.substring(with: paragraphMatch.range(at: 1)) as NSString
            var values: [String: Double] = [:]
            for match in attributeExpression.matches(in: attributes as String, range: NSRange(location: 0, length: attributes.length)) {
                guard match.numberOfRanges > 2 else { continue }
                let name = attributes.substring(with: match.range(at: 1)).lowercased()
                guard let value = Double(attributes.substring(with: match.range(at: 2))), value.isFinite else { continue }
                values[name] = value
            }
            guard let firstLine = values["data-note-first-line-head-indent"],
                  let head = values["data-note-head-indent"],
                  let tail = values["data-note-tail-indent"] else { return nil }
            return NativeRichTextNoteParagraphHTMLIndent(
                firstLineHeadIndent: firstLine,
                headIndent: head,
                tailIndent: tail
            )
        }
    }

    private static func approximately(_ value: Double, _ target: Double) -> Bool {
        value.isFinite && abs(value - target) < 0.01
    }
}
