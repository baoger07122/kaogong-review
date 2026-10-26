import Foundation

enum QuestionBankMultiBlankOptionText {
    static let canonicalSeparator = "    "

    enum Format: Equatable {
        case fourSpaces
        case legacySingleSpace
        case legacySemicolon
    }

    struct Parsed: Equatable {
        let groups: [String]
        let format: Format
    }

    static func blankCount(in stem: String) -> Int {
        let patterns = [#"(?:_{2,}|＿{2,})"#, #"[（(]\s*[）)]"#]
        return patterns.reduce(0) { total, pattern in
            guard let expression = try? NSRegularExpression(pattern: pattern) else { return total }
            let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)
            return total + expression.numberOfMatches(in: stem, range: range)
        }
    }

    static func parse(_ text: String, blankCount: Int) -> Parsed? {
        guard blankCount > 1 else { return nil }
        let expectedGroupCount = blankCount
        guard text == text.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }

        if text.contains(canonicalSeparator) {
            let groups = text.components(separatedBy: canonicalSeparator)
            guard groups.count == expectedGroupCount,
                  groups.allSatisfy(isCleanGroup),
                  !groups.contains(where: { $0.contains(";") || $0.contains("；") }),
                  !containsAmbiguousWhitespaceRun(in: groups) else { return nil }
            return Parsed(groups: groups, format: .fourSpaces)
        }

        if text.contains(";") || text.contains("；") {
            guard !text.contains(" "), !text.contains("\t"), !text.contains("\n") else { return nil }
            let groups = text.components(separatedBy: CharacterSet(charactersIn: ";；"))
            guard groups.count == expectedGroupCount, groups.allSatisfy(isCleanGroup) else { return nil }
            return Parsed(groups: groups, format: .legacySemicolon)
        }

        // One ASCII space is accepted for legacy packages such as the 2019
        // combined verbal exam. More whitespace is ambiguous and must be
        // checked against the source instead of guessed.
        guard text.contains(" "), !text.contains("  "),
              !text.contains("\t"), !text.contains("\n") else { return nil }
        let groups = text.components(separatedBy: " ")
        guard groups.count == expectedGroupCount, groups.allSatisfy(isCleanGroup) else { return nil }
        return Parsed(groups: groups, format: .legacySingleSpace)
    }

    static func validationMessage(for text: String, blankCount: Int) -> String? {
        guard blankCount > 1, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              parse(text, blankCount: blankCount) == nil else { return nil }
        return "多空逻辑填空的词语边界无法确认。请对照原卷核对后用恰好 4 个半角空格分隔词语；旧单空格和分号格式仍可读取。导入器不会猜测中文词语边界。"
    }

    private static func isCleanGroup(_ value: String) -> Bool {
        !value.isEmpty && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsAmbiguousWhitespaceRun(in groups: [String]) -> Bool {
        groups.contains { group in
            group.range(of: #" {2,}"#, options: .regularExpression) != nil
        }
    }
}
