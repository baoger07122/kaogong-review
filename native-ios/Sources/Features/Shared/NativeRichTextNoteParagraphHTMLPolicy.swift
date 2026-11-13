import Foundation

struct NativeRichTextNoteParagraphHTMLStyle: Equatable, Sendable {
    var spacingBefore: Double
    var spacingAfter: Double
    var lineSpacing: Double
    var fontSize: Double
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
        guard !declarations.isEmpty,
              let expression = try? NSRegularExpression(pattern: #"(?i)^<(p|h[1-6])>"#),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(match.range(at: 1), in: html),
              let fullRange = Range(match.range, in: html) else { return html }
        let tag = String(html[tagRange])
        let replacement = "<\(tag) style=\"\(declarations.joined(separator: "; "))\">"
        return html.replacingCharacters(in: fullRange, with: replacement)
    }

    private static func approximately(_ value: Double, _ target: Double) -> Bool {
        value.isFinite && abs(value - target) < 0.01
    }
}
