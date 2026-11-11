import Foundation

enum LibraryDataAnalysisCauseLayout {
    static func usesTextCause(subject: String, module: String) -> Bool {
        subject == "资料分析" || (subject == "言语理解" && module == "逻辑填空")
    }

    static func splitLines(_ text: String) -> [String] {
        text.components(separatedBy: .newlines)
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

    static func estimatedTagLineHeight(label: String, values: [String], width: CGFloat) -> CGFloat {
        guard !values.isEmpty else { return 0 }

        let labelWidth = CGFloat(label.count + 1) * 12
        let textWidth = max(1, width - labelWidth - 5 - 14)
        let fontSize: CGFloat = 11
        let verticalPadding: CGFloat = 10
        let lineHeight = fontSize * 1.35
        let spacing: CGFloat = 5
        let rowsHeight = values.reduce(CGFloat(0)) { total, value in
            let lineCount = max(1, Int(ceil(CGFloat(value.count) * fontSize / textWidth)))
            return total + CGFloat(lineCount) * lineHeight + verticalPadding
        }
        return max(14, rowsHeight + CGFloat(max(0, values.count - 1)) * spacing)
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
