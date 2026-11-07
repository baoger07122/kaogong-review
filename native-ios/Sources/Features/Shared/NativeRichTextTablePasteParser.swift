import Foundation

struct NativeRichTextPastedTable: Equatable {
    let range: NSRange
    let cells: [[String]]
}

enum NativeRichTextTablePasteParser {
    private static let maximumColumns = 8
    private static let maximumRows = 16
    private static let maximumCellBytes = 512

    static func markdownTables(in source: String) -> [NativeRichTextPastedTable] {
        let text = normalizeLineEndings(source)
        let lines = lineRanges(in: text)
        guard lines.count >= 3 else { return [] }
        var result: [NativeRichTextPastedTable] = []
        var inFence = false
        var index = 0

        while index < lines.count {
            let line = lines[index].text.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                inFence.toggle()
                index += 1
                continue
            }
            guard !inFence,
                  index + 2 < lines.count,
                  let header = markdownCells(lines[index].text),
                  let separator = markdownCells(lines[index + 1].text),
                  header.count >= 2,
                  header.count <= maximumColumns,
                  separator.count == header.count,
                  separator.allSatisfy(isMarkdownSeparator) else {
                index += 1
                continue
            }

            var rows = [header]
            var lastLine = index
            var cursor = index + 2
            var exceededMaximumRows = false
            while cursor < lines.count, rows.count < maximumRows {
                let candidate = lines[cursor].text.trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || candidate.hasPrefix("```") || candidate.hasPrefix("~~~") { break }
                guard let cells = markdownCells(lines[cursor].text), cells.count == header.count else { break }
                rows.append(cells.map(normalizeMarkdownCell))
                lastLine = cursor
                cursor += 1
            }
            if rows.count == maximumRows, cursor < lines.count,
               let extraRow = markdownCells(lines[cursor].text), extraRow.count == header.count {
                exceededMaximumRows = true
            }
            if exceededMaximumRows {
                while cursor < lines.count,
                      let extraRow = markdownCells(lines[cursor].text), extraRow.count == header.count {
                    cursor += 1
                }
                index = cursor
                continue
            }
            guard rows.count >= 2,
                  rows.allSatisfy({ $0.count == header.count && $0.allSatisfy(isSafeCell) }) else {
                index += 1
                continue
            }
            rows[0] = rows[0].map(normalizeMarkdownCell)
            let start = lines[index].range.location
            let end = NSMaxRange(lines[lastLine].contentRange)
            result.append(NativeRichTextPastedTable(
                range: NSRange(location: start, length: max(0, end - start)),
                cells: rows
            ))
            index = lastLine + 1
        }
        return result
    }

    static func containsHTMLTable(_ source: String) -> Bool {
        source.range(of: #"<table\b"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// Returns nil when a table is present but cannot be represented safely.
    static func htmlTables(in source: String) -> [NativeRichTextPastedTable]? {
        guard containsHTMLTable(source) else { return [] }
        let sourceNSString = source as NSString
        guard let tableExpression = try? NSRegularExpression(pattern: #"(?is)<table\b[^>]*>(.*?)</table\s*>"#) else { return nil }
        let tableMatches = tableExpression.matches(in: source, range: NSRange(location: 0, length: sourceNSString.length))
        guard !tableMatches.isEmpty else { return nil }

        var result: [NativeRichTextPastedTable] = []
        for tableMatch in tableMatches {
            guard tableMatch.numberOfRanges > 1 else { return nil }
            let tableBody = sourceNSString.substring(with: tableMatch.range(at: 1))
            guard !containsUnsafeTableContent(tableBody),
                  let rowsExpression = try? NSRegularExpression(pattern: #"(?is)<tr\b[^>]*>(.*?)</tr\s*>"#) else { return nil }
            let tableBodyNSString = tableBody as NSString
            let rowMatches = rowsExpression.matches(in: tableBody, range: NSRange(location: 0, length: tableBodyNSString.length))
            guard rowMatches.count >= 2, rowMatches.count <= maximumRows else { return nil }
            var rows: [[String]] = []
            var expectedColumns: Int?

            for rowMatch in rowMatches {
                let rowHTML = tableBodyNSString.substring(with: rowMatch.range(at: 1))
                guard let cellExpression = try? NSRegularExpression(pattern: #"(?is)<(td|th)\b([^>]*)>(.*?)</\1\s*>"#) else { return nil }
                let rowHTMLNSString = rowHTML as NSString
                let cellMatches = cellExpression.matches(in: rowHTML, range: NSRange(location: 0, length: rowHTMLNSString.length))
                let columns = cellMatches.map { match -> String in
                    let raw = rowHTMLNSString.substring(with: match.range(at: 3))
                    return htmlCellText(raw)
                }
                guard !columns.isEmpty,
                      columns.count <= maximumColumns,
                      expectedColumns == nil || expectedColumns == columns.count else { return nil }
                expectedColumns = columns.count
                guard columns.allSatisfy(isSafeCell) else { return nil }
                rows.append(columns)
            }
            guard let columns = expectedColumns, columns >= 2, rows.count >= 2 else { return nil }
            result.append(NativeRichTextPastedTable(range: tableMatch.range, cells: rows))
        }
        return result
    }

    static func normalizeLineEndings(_ value: String) -> String {
        value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private struct Line {
        let text: String
        let range: NSRange
        let contentRange: NSRange
    }

    private static func lineRanges(in value: String) -> [Line] {
        let source = value as NSString
        var result: [Line] = []
        var location = 0
        while location < source.length {
            let range = source.lineRange(for: NSRange(location: location, length: 0))
            var contentRange = range
            while contentRange.length > 0 {
                let last = source.character(at: NSMaxRange(contentRange) - 1)
                if last == 10 || last == 13 { contentRange.length -= 1 }
                else { break }
            }
            result.append(Line(
                text: source.substring(with: contentRange),
                range: range,
                contentRange: contentRange
            ))
            location = NSMaxRange(range)
        }
        if source.length == 0 { return [] }
        return result
    }

    private static func markdownCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("|") else { return nil }
        let body = String(trimmed.dropFirst(trimmed.hasPrefix("|") ? 1 : 0).dropLast(trimmed.hasSuffix("|") ? 1 : 0))
        var cells: [String] = []
        var current = ""
        var escaped = false
        for character in body {
            if escaped {
                if character == "|" { current.append(character) }
                else { current.append("\\"); current.append(character) }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(character)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells.count >= 2 ? cells : nil
    }

    private static func isMarkdownSeparator(_ value: String) -> Bool {
        value.range(of: #"^:?-{3,}:?$"#, options: .regularExpression) != nil
    }

    private static func normalizeMarkdownCell(_ value: String) -> String {
        value.replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSafeCell(_ value: String) -> Bool {
        value.utf8.count <= maximumCellBytes
    }

    private static func containsUnsafeTableContent(_ value: String) -> Bool {
        let unsafe = #"(?is)<(?:table|script|style|iframe|object|embed|img|picture|video|audio|svg|canvas)\b|\b(?:rowspan|colspan)\s*="#
        return value.range(of: unsafe, options: .regularExpression) != nil
    }

    private static func htmlCellText(_ html: String) -> String {
        var value = html
        value = value.replacingOccurrences(of: #"(?is)<br\s*/?>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?is)</(?:p|div|li|blockquote|h[1-6])\s*>"#, with: "\n", options: .regularExpression)
        value = value.replacingOccurrences(of: #"(?is)<[^>]+>"#, with: "", options: .regularExpression)
        value = decodeHTMLEntities(value)
        return value.replacingOccurrences(of: "\u{00a0}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTMLEntities(_ source: String) -> String {
        var value = source
        let named: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
            "&#39;": "'", "&nbsp;": " ", "&ndash;": "–", "&mdash;": "—", "&hellip;": "…",
            "&ldquo;": "“", "&rdquo;": "”", "&lsquo;": "‘", "&rsquo;": "’"
        ]
        for (encoded, decoded) in named { value = value.replacingOccurrences(of: encoded, with: decoded, options: .caseInsensitive) }
        guard let expression = try? NSRegularExpression(pattern: #"&#(?:x([0-9a-fA-F]+)|([0-9]+));"#) else { return value }
        let nsValue = value as NSString
        for match in expression.matches(in: value, range: NSRange(location: 0, length: nsValue.length)).reversed() {
            let digitsRange = match.range(at: match.range(at: 1).location == NSNotFound ? 2 : 1)
            let digits = nsValue.substring(with: digitsRange)
            let radix = match.range(at: 1).location == NSNotFound ? 10 : 16
            guard let number = UInt32(digits, radix: radix), let scalar = UnicodeScalar(number) else { continue }
            value = (value as NSString).replacingCharacters(in: match.range, with: String(scalar))
        }
        return value
    }
}
