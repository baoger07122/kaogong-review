import Foundation

enum LibraryErrorCauseCompatibility {
    static func isCenterUnderstanding(subject: String?, module: String?) -> Bool {
        normalized(subject) == "言语理解" && normalized(module) == "中心理解"
    }

    static func usesLineEditor(subject: String?, module: String?) -> Bool {
        let normalizedSubject = normalized(subject)
        let normalizedModule = normalized(module)
        if normalizedSubject == "资料分析" { return true }
        return normalizedSubject == "言语理解"
            && ["中心理解", "逻辑填空"].contains(normalizedModule)
    }

    static func excludesFromCauseTagFiltering(subject: String?, module: String?) -> Bool {
        let normalizedSubject = normalized(subject)
        let normalizedModule = normalized(module)
        return normalizedSubject == "言语理解"
            && ["中心理解", "逻辑填空"].contains(normalizedModule)
    }

    static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .flatMap { line in
                // Old tag selection saved multiple causes with `、`. Commas and
                // sentence punctuation stay inside free-text causes.
                line.components(separatedBy: "、")
            }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    static func splitLines(_ value: Any?) -> [String] {
        if let values = value as? [String] { return values.flatMap(splitLines) }
        return splitLines(value as? String ?? "")
    }

    static func rawCause(in object: [String: Any]) -> String {
        if let canonical = object["errorCause"] {
            return splitLines(canonical).joined(separator: "\n")
        }
        for key in ["cause", "reason"] {
            let lines = splitLines(object[key])
            if !lines.isEmpty { return lines.joined(separator: "\n") }
        }
        return ""
    }

    private static func normalized(_ value: String?) -> String {
        var value = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for pattern in [
            "^[一二三四五六七八九十百]+[、.．)）]\\s*",
            "^[0-9]+[、.．)）]\\s*",
            "^[（(][一二三四五六七八九十百]+[）)]\\s*"
        ] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum LibraryDataAnalysisCauseLayout {
    static func splitLines(_ text: String) -> [String] {
        LibraryErrorCauseCompatibility.splitLines(text)
    }

    static func splitLines(_ value: Any?) -> [String] {
        LibraryErrorCauseCompatibility.splitLines(value)
    }

    static func rawCause(in object: [String: Any]) -> String {
        LibraryErrorCauseCompatibility.rawCause(in: object)
    }

    static func estimatedTagLineHeight(label: String, values: [String], width: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }

        let labelWidth = CGFloat(label.count + 1) * 12
        let flowWidth = max(1, width - labelWidth - 5)
        let fontSize: CGFloat = 11
        let horizontalPadding: CGFloat = 14
        let verticalPadding: CGFloat = 10
        let lineHeight = fontSize * 1.35
        let spacing: CGFloat = 5
        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0

        for value in values {
            let naturalWidth = CGFloat(value.count) * fontSize + horizontalPadding
            let itemWidth = min(flowWidth, naturalWidth)
            let textWidth = max(1, flowWidth - horizontalPadding)
            let lineCount = max(1, Int(ceil(CGFloat(value.count) * fontSize / textWidth)))
            let itemHeight = CGFloat(lineCount) * lineHeight + verticalPadding

            if rowWidth > 0, rowWidth + spacing + itemWidth > flowWidth {
                totalHeight += rowHeight + spacing
                rowWidth = 0
                rowHeight = 0
            }

            rowWidth += (rowWidth > 0 ? spacing : 0) + itemWidth
            rowHeight = max(rowHeight, itemHeight)
        }

        return max(14, totalHeight + rowHeight)
    }
}

enum LibraryLogicComparisonLayout {
    static func terms(in text: String) -> [String] {
        let normalized = text.replacingOccurrences(
            of: #"(?i)(?<![A-Za-z])vs\.?(?![A-Za-z])"#,
            with: "|",
            options: .regularExpression
        )
        let values = normalized.split(whereSeparator: { "、,，;；/／|｜".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return values.isEmpty && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? [text.trimmingCharacters(in: .whitespacesAndNewlines)]
            : values
    }

    static func preview(_ text: String, contextLength: Int = 24) -> String {
        let pattern = #"_{2,}|＿{2,}|（\s*）|\(\s*\)|\[\s*\]"#
        guard let range = text.range(of: pattern, options: .regularExpression) else { return text }
        let start = text.index(range.lowerBound, offsetBy: -contextLength, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(range.upperBound, offsetBy: contextLength, limitedBy: text.endIndex) ?? text.endIndex
        let prefix = start == text.startIndex ? "" : "…"
        let suffix = end == text.endIndex ? "" : "…"
        let snippetRange = NSRange(start..<end, in: text)
        let snippet = (text as NSString).substring(with: snippetRange)
        return prefix + snippet + suffix
    }
}
