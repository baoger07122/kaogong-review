import Foundation

struct NativeRichTextPastedTable: Equatable {
    let range: NSRange
    let cells: [[String]]
    let boldRanges: [NativeRichTextPastedBoldRange]
}

struct NativeRichTextPastedBoldRange: Codable, Equatable {
    let row: Int
    let column: Int
    let location: Int
    let length: Int
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

            var rows: [[String]] = []
            var boldRanges: [NativeRichTextPastedBoldRange] = []
            appendMarkdownRow(header, rowIndex: 0, rows: &rows, boldRanges: &boldRanges)
            var lastLine = index
            var cursor = index + 2
            var exceededMaximumRows = false
            while cursor < lines.count, rows.count < maximumRows {
                let candidate = lines[cursor].text.trimmingCharacters(in: .whitespaces)
                if candidate.isEmpty || candidate.hasPrefix("```") || candidate.hasPrefix("~~~") { break }
                guard let cells = markdownCells(lines[cursor].text), cells.count == header.count else { break }
                appendMarkdownRow(cells, rowIndex: rows.count, rows: &rows, boldRanges: &boldRanges)
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
            let start = lines[index].range.location
            let end = NSMaxRange(lines[lastLine].contentRange)
            result.append(NativeRichTextPastedTable(
                range: NSRange(location: start, length: max(0, end - start)),
                cells: rows,
                boldRanges: boldRanges
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
            var boldRanges: [NativeRichTextPastedBoldRange] = []
            var expectedColumns: Int?

            for rowMatch in rowMatches {
                let rowHTML = tableBodyNSString.substring(with: rowMatch.range(at: 1))
                guard let cellExpression = try? NSRegularExpression(pattern: #"(?is)<(td|th)\b([^>]*)>(.*?)</\1\s*>"#) else { return nil }
                let rowHTMLNSString = rowHTML as NSString
                let cellMatches = cellExpression.matches(in: rowHTML, range: NSRange(location: 0, length: rowHTMLNSString.length))
                var columns: [String] = []
                for (columnIndex, match) in cellMatches.enumerated() {
                    let raw = rowHTMLNSString.substring(with: match.range(at: 3))
                    let parsed = htmlCellContent(raw)
                    columns.append(parsed.text)
                    boldRanges.append(contentsOf: parsed.ranges.map {
                        NativeRichTextPastedBoldRange(row: rows.count, column: columnIndex, location: $0.location, length: $0.length)
                    })
                }
                guard !columns.isEmpty,
                      columns.count <= maximumColumns,
                      expectedColumns == nil || expectedColumns == columns.count else { return nil }
                expectedColumns = columns.count
                guard columns.allSatisfy(isSafeCell) else { return nil }
                rows.append(columns)
            }
            guard let columns = expectedColumns, columns >= 2, rows.count >= 2 else { return nil }
            result.append(NativeRichTextPastedTable(range: tableMatch.range, cells: rows, boldRanges: boldRanges))
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

    private static func appendMarkdownRow(
        _ rawCells: [String],
        rowIndex: Int,
        rows: inout [[String]],
        boldRanges: inout [NativeRichTextPastedBoldRange]
    ) {
        var row: [String] = []
        for (column, raw) in rawCells.enumerated() {
            let parsed = markdownCellContent(raw)
            row.append(parsed.text)
            boldRanges.append(contentsOf: parsed.ranges.map {
                NativeRichTextPastedBoldRange(row: rowIndex, column: column, location: $0.location, length: $0.length)
            })
        }
        rows.append(row)
    }

    private static func markdownCellContent(_ value: String) -> (text: String, ranges: [NSRange]) {
        let source = normalizeMarkdownCell(value)
        guard let expression = try? NSRegularExpression(pattern: #"(?s)(?<!\\)(\*\*|__)(?=\S)(.+?)(?<=\S)\1"#) else {
            return (source, [])
        }
        let sourceNSString = source as NSString
        let matches = expression.matches(in: source, range: NSRange(location: 0, length: sourceNSString.length))
        guard !matches.isEmpty else { return (source, []) }
        var output = ""
        var ranges: [NSRange] = []
        var cursor = 0
        for match in matches {
            guard match.numberOfRanges > 2 else { continue }
            let contentRange = match.range(at: 2)
            guard contentRange.location != NSNotFound, contentRange.length > 0 else { continue }
            if match.range.location > cursor {
                output += sourceNSString.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            }
            let start = (output as NSString).length
            let content = sourceNSString.substring(with: contentRange)
            output += content
            ranges.append(NSRange(location: start, length: (content as NSString).length))
            cursor = NSMaxRange(match.range)
        }
        if cursor < sourceNSString.length { output += sourceNSString.substring(from: cursor) }
        return trimmed(output, ranges: ranges)
    }

    private static func isSafeCell(_ value: String) -> Bool {
        value.utf8.count <= maximumCellBytes
    }

    private static func containsUnsafeTableContent(_ value: String) -> Bool {
        let unsafe = #"(?is)<(?:table|script|style|iframe|object|embed|img|picture|video|audio|svg|canvas)\b|\b(?:rowspan|colspan)\s*="#
        return value.range(of: unsafe, options: .regularExpression) != nil
    }

    private static func htmlCellContent(_ html: String) -> (text: String, ranges: [NSRange]) {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<(/?)([a-z0-9]+)\b([^>]*)>"#) else {
            return (decodeHTMLEntities(html), [])
        }
        let source = html as NSString
        let matches = expression.matches(in: html, range: NSRange(location: 0, length: source.length))
        var output = ""
        var ranges: [NSRange] = []
        var stack: [(name: String, bold: Bool)] = []
        var boldDepth = 0
        var boldStart: Int?
        var cursor = 0

        func appendText(_ raw: String) {
            let decoded = decodeHTMLEntities(raw).replacingOccurrences(of: "\u{00a0}", with: " ")
            output += decoded
        }

        func closeBoldRun() {
            guard let start = boldStart else { return }
            let length = (output as NSString).length - start
            if length > 0 { ranges.append(NSRange(location: start, length: length)) }
            boldStart = nil
        }

        for match in matches {
            if match.range.location > cursor {
                appendText(source.substring(with: NSRange(location: cursor, length: match.range.location - cursor)))
            }
            let closing = source.substring(with: match.range(at: 1)) == "/"
            let name = source.substring(with: match.range(at: 2)).lowercased()
            let attributes = source.substring(with: match.range(at: 3))
            if closing {
                if let stackIndex = stack.lastIndex(where: { $0.name == name }) {
                    let removed = stack[stackIndex...]
                    for item in removed where item.bold { boldDepth = max(0, boldDepth - 1) }
                    stack.removeSubrange(stackIndex...)
                    if boldDepth == 0 { closeBoldRun() }
                }
                if ["p", "div", "li", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"].contains(name),
                   !output.hasSuffix("\n") { output += "\n" }
            } else if name == "br" {
                output += "\n"
            } else {
                let isBold = name == "strong" || name == "b" || hasBoldFontWeight(attributes)
                stack.append((name, isBold))
                if isBold {
                    if boldDepth == 0 { boldStart = (output as NSString).length }
                    boldDepth += 1
                }
            }
            cursor = NSMaxRange(match.range)
        }
        if cursor < source.length { appendText(source.substring(from: cursor)) }
        if boldDepth > 0 { closeBoldRun() }
        return trimmed(output, ranges: ranges)
    }

    private static func hasBoldFontWeight(_ attributes: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"font-weight\s*:\s*(bold|[0-9]{1,4})"#, options: .caseInsensitive) else {
            return false
        }
        let source = attributes as NSString
        let matches = expression.matches(in: attributes, range: NSRange(location: 0, length: source.length))
        return matches.contains { match in
            guard match.numberOfRanges > 1 else { return false }
            let weight = source.substring(with: match.range(at: 1)).lowercased()
            return weight == "bold" || (Int(weight).map { $0 >= 600 } ?? false)
        }
    }

    private static func trimmed(_ value: String, ranges: [NSRange]) -> (text: String, ranges: [NSRange]) {
        let leading = value.prefix(while: { $0.isWhitespace }).reduce(0) { $0 + String($1).utf16.count }
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLength = (trimmedValue as NSString).length
        let upperBound = leading + trimmedLength
        let adjusted = ranges.compactMap { range -> NSRange? in
            let start = max(range.location, leading)
            let end = min(NSMaxRange(range), upperBound)
            guard start < end else { return nil }
            return NSRange(location: start - leading, length: end - start)
        }
        return (trimmedValue, adjusted)
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
