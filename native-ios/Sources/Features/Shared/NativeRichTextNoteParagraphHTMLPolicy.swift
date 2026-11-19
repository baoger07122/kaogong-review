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

struct NativeRichTextNoteParagraphHTMLMetadata: Equatable, Sendable {
    var tagName: String
    var headingLevel: Int?
    var versionedLayout: NativeRichTextNoteParagraphHTMLStyle?
    var hasExplicitSpacing: Bool
    var cssSpacing: NativeRichTextNoteParagraphHTMLSpacing? = nil
}

struct NativeRichTextNoteParagraphHTMLSpacing: Equatable, Sendable {
    var before: Double
    var after: Double
}

enum NativeRichTextNoteParagraphHTMLPolicy {
    static func metadata(in html: String) -> [NativeRichTextNoteParagraphHTMLMetadata] {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<(p|h([1-6]))\b([^>]*)>"#) else { return [] }
        let source = html as NSString
        return expression.matches(in: html, range: NSRange(location: 0, length: source.length)).map { match in
            guard match.numberOfRanges > 3 else {
                return NativeRichTextNoteParagraphHTMLMetadata(tagName: "p", headingLevel: nil, versionedLayout: nil, hasExplicitSpacing: false)
            }
            let tagName = source.substring(with: match.range(at: 1)).lowercased()
            let attributes = source.substring(with: match.range(at: 3))
            let storedHeadingLevel = attribute("data-native-rich-text-heading-level", in: attributes).flatMap { Int($0) }
            let tagHeadingLevel = match.range(at: 2).location == NSNotFound
                ? nil
                : Int(source.substring(with: match.range(at: 2)))
            let headingLevel = storedHeadingLevel ?? tagHeadingLevel
            let layoutVersion = attribute("data-note-layout-version", in: attributes)
            let before = attribute("data-note-spacing-before", in: attributes).flatMap { Double($0) }
            let after = attribute("data-note-spacing-after", in: attributes).flatMap { Double($0) }
            let line = attribute("data-note-line-spacing", in: attributes).flatMap { Double($0) }
            let indentMetadata = indents(in: "<\(tagName) \(attributes)>").first ?? nil
            let layout: NativeRichTextNoteParagraphHTMLStyle?
            if layoutVersion == "1",
               let before, before.isFinite,
               let after, after.isFinite,
               let line, line.isFinite {
                layout = NativeRichTextNoteParagraphHTMLStyle(
                    spacingBefore: before,
                    spacingAfter: after,
                    lineSpacing: line,
                    fontSize: 16,
                    firstLineHeadIndent: indentMetadata?.firstLineHeadIndent ?? 0,
                    headIndent: indentMetadata?.headIndent ?? 0,
                    tailIndent: indentMetadata?.tailIndent ?? 0
                )
            } else {
                layout = nil
            }
            let css = attribute("style", in: attributes) ?? ""
            let cssSpacing = spacingDeclarations(in: css)
            let hasExplicitSpacing = layout != nil
                || before != nil
                || after != nil
                || attribute("data-native-rich-text-explicit-spacing", in: attributes) == "1"
                || cssSpacing != nil
                || css.range(of: #"(?i)(?:^|;)\s*-apple-paragraph-spacing\s*:"#, options: .regularExpression) != nil
            return NativeRichTextNoteParagraphHTMLMetadata(
                tagName: tagName,
                headingLevel: headingLevel,
                versionedLayout: layout,
                hasExplicitSpacing: hasExplicitSpacing,
                cssSpacing: cssSpacing
            )
        }
    }

    static func paragraphsMatch(_ first: [String], _ second: [String]) -> Bool {
        guard first.count == second.count else { return false }
        return zip(first, second).allSatisfy { pair in
            normalizeParagraphText(pair.0) == normalizeParagraphText(pair.1)
        }
    }

    static func normalizingPastedStyles(
        _ source: [NativeRichTextNoteParagraphHTMLStyle],
        hasContent: [Bool],
        isQuoted: [Bool],
        isList: [Bool],
        preservesParagraphLayout: [Bool],
        metadata: [NativeRichTextNoteParagraphHTMLMetadata?],
        hasStructuredParagraphs: Bool
    ) -> [NativeRichTextNoteParagraphHTMLStyle] {
        let count = source.count
        guard hasContent.count == count,
              isQuoted.count == count,
              isList.count == count,
              preservesParagraphLayout.count == count,
              metadata.count == count else { return source }

        func clamp(_ value: Double, _ limit: Double) -> Double {
            guard value.isFinite else { return 0 }
            return min(limit, max(0, value))
        }
        func hasSavedLayout(_ index: Int) -> Bool { metadata[index]?.versionedLayout != nil }
        func ordinaryParagraph(_ index: Int) -> Bool {
            hasContent[index] && !isQuoted[index] && !isList[index] && !preservesParagraphLayout[index] && !hasSavedLayout(index)
        }

        var result = source
        for index in source.indices {
            guard hasContent[index], !preservesParagraphLayout[index], !hasSavedLayout(index) else { continue }
            if isQuoted[index] {
                result[index].spacingBefore = clamp(source[index].spacingBefore, 4)
                result[index].spacingAfter = 5
                result[index].lineSpacing = clamp(source[index].lineSpacing, 2)
            } else if isList[index] {
                result[index].spacingBefore = 0
                result[index].spacingAfter = 0
                result[index].lineSpacing = 0
            } else {
                result[index].spacingBefore = clamp(source[index].spacingBefore, 4)
                result[index].spacingAfter = clamp(source[index].spacingAfter, 4)
                result[index].lineSpacing = source[index].lineSpacing > 0.01
                    ? clamp(source[index].lineSpacing, 1)
                    : (hasStructuredParagraphs ? 1 : 0)
            }
        }

        guard hasStructuredParagraphs, count > 1 else { return result }
        for index in 1..<count where ordinaryParagraph(index - 1) && ordinaryParagraph(index) {
            let sourceGap = clamp(source[index - 1].spacingAfter, 4) + clamp(source[index].spacingBefore, 4)
            let explicitGap = metadata[index - 1]?.hasExplicitSpacing == true
                || metadata[index]?.hasExplicitSpacing == true
                || sourceGap > 0.01
            result[index - 1].spacingAfter = explicitGap ? min(4, sourceGap) : 4
            result[index].spacingBefore = 0
        }
        return result
    }

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
        guard let expression = try? NSRegularExpression(pattern: #"(?i)^<(p|h[1-6])\b([^>]*)>"#),
              let match = expression.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let tagRange = Range(match.range(at: 1), in: html),
              let fullRange = Range(match.range, in: html) else { return html }
        let tag = String(html[tagRange])
        var attributes: [String] = []
        if !declarations.isEmpty {
            attributes.append("style=\"\(declarations.joined(separator: "; "))\"")
        }
        attributes.append("data-note-layout-version=\"1\"")
        attributes.append("data-note-spacing-before=\"\(finiteOrZero(style.spacingBefore))\"")
        attributes.append("data-note-spacing-after=\"\(finiteOrZero(style.spacingAfter))\"")
        attributes.append("data-note-line-spacing=\"\(finiteOrZero(style.lineSpacing))\"")
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

    private static func attribute(_ name: String, in source: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(pattern: "(?i)\\b\(escaped)\\s*=\\s*[\\\"']([^\\\"']*)[\\\"']"),
              let match = expression.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: source) else { return nil }
        return String(source[range])
    }

    private static func finiteOrZero(_ value: Double) -> Double { value.isFinite ? value : 0 }

    private static func spacingDeclarations(in css: String) -> NativeRichTextNoteParagraphHTMLSpacing? {
        var before: Double?
        var after: Double?
        for declaration in css.split(separator: ";") {
            let pair = declaration.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            guard pair.count == 2 else { continue }
            switch pair[0] {
            case "margin-top":
                if let length = cssLength(pair[1]) { before = length }
            case "margin-bottom":
                if let length = cssLength(pair[1]) { after = length }
            case "margin":
                let rawValues = pair[1].split(whereSeparator: \.isWhitespace)
                let values = rawValues.compactMap { cssLength(String($0)) }
                guard !values.isEmpty, values.count == rawValues.count, values.count <= 4 else { continue }
                before = values[0]
                after = values.count == 1 ? values[0] : values[countIndexForBottom(values.count)]
            default: continue
            }
        }
        guard before != nil || after != nil else { return nil }
        return NativeRichTextNoteParagraphHTMLSpacing(before: before ?? 0, after: after ?? 0)
    }

    private static func countIndexForBottom(_ count: Int) -> Int {
        count == 2 ? 1 : (count == 3 ? 2 : 2)
    }

    private static func cssLength(_ raw: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: #"^(-?(?:\d+\.?\d*|\.\d+))(pt|px)?$"#),
              let match = expression.firstMatch(in: raw, range: NSRange(raw.startIndex..., in: raw)),
              match.numberOfRanges > 1,
              let numberRange = Range(match.range(at: 1), in: raw),
              var value = Double(raw[numberRange]), value.isFinite else { return nil }
        if match.numberOfRanges > 2,
           match.range(at: 2).location != NSNotFound,
           let unitRange = Range(match.range(at: 2), in: raw),
           raw[unitRange] == "px" {
            value *= 0.75
        }
        return value
    }

    private static func normalizeParagraphText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .precomposedStringWithCanonicalMapping
    }
}
