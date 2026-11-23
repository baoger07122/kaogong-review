import Foundation

enum ShenlunMaterialTextFormatter {
    private static let materialHeading = #"^(?:给定)?材料[ \t　]*[0-9０-９一二三四五六七八九十]+[：:]?$"#
    private static let numberedItem = #"^(?:[一二三四五六七八九十]+[、．]|[（(][一二三四五六七八九十0-9０-９]+[）)]|[0-9０-９]+[、．]|[0-9]+\.[ \t]|[•●▪]|[-*][ \t])"#
    private static let closingPunctuation = "，。！？；：、）》】〕〉”’」』…％,.!?;:)]}"
    private static let closingQuotesAndBrackets = "）》】〕〉”’」』)]}"

    static func format(_ text: String) -> String {
        let copy = text.replacingOccurrences(of: "\u{2029}", with: "\n\n")
        var lines: [Line] = []
        var afterBlank = false
        for rawLine in copy.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let content = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else {
                afterBlank = true
                continue
            }

            let indented = rawLine.hasPrefix("　") || rawLine.hasPrefix("\t") || rawLine.hasPrefix("  ")
            lines.append(Line(text: content, hasParagraphBoundary: indented || afterBlank))
            afterBlank = false
        }
        guard let first = lines.first, lines.count > 1 else { return text }

        let hasExplicitParagraphs = lines.dropFirst().contains { $0.hasParagraphBoundary || $0.isNumberedItem }
        // A short sentence-ending line is likelier to mark the end of a paragraph
        // than one that fills the original PDF column.
        let proseWidths = lines.filter { !$0.isMaterialHeading }.map { $0.text.count }.sorted()
        let shortLineLimit: Int
        if !hasExplicitParagraphs, proseWidths.count >= 3 {
            shortLineLimit = proseWidths[(proseWidths.count - 1) * 4 / 5] * 4 / 5
        } else {
            shortLineLimit = 0
        }

        var paragraphs: [String] = []
        var paragraph = first.text
        var previous = first
        for line in lines.dropFirst() {
            let inferredBoundary = previous.text.count <= shortLineLimit && endsSentence(previous.text)
                && !line.text.prefix(1).contains(where: closingPunctuation.contains)
            if line.hasParagraphBoundary || line.isMaterialHeading || line.isNumberedItem
                || previous.isMaterialHeading || inferredBoundary {
                paragraphs.append(paragraph)
                paragraph = line.text
            } else {
                if let left = previous.text.last, let right = line.text.first,
                   needsWordSpace(between: left, and: right) {
                    paragraph.append(" ")
                }
                paragraph.append(line.text)
            }
            previous = line
        }
        paragraphs.append(paragraph)
        return paragraphs.joined(separator: "\n\n")
    }

    private static func endsSentence(_ text: String) -> Bool {
        guard let end = text.reversed().first(where: { !closingQuotesAndBrackets.contains($0) }) else { return false }
        return "。！？".contains(end)
    }

    private static func needsWordSpace(between left: Character, and right: Character) -> Bool {
        guard left.isASCII, right.isASCII, right.isLetter || right.isNumber else { return false }
        return left.isLetter || left.isNumber || ",;:!?".contains(left)
    }

    private struct Line {
        let text: String
        let hasParagraphBoundary: Bool
        let isMaterialHeading: Bool
        let isNumberedItem: Bool

        init(text: String, hasParagraphBoundary: Bool) {
            self.text = text
            self.hasParagraphBoundary = hasParagraphBoundary
            isMaterialHeading = text.range(of: ShenlunMaterialTextFormatter.materialHeading, options: .regularExpression) != nil
            isNumberedItem = text.range(of: ShenlunMaterialTextFormatter.numberedItem, options: .regularExpression) != nil
        }
    }
}
