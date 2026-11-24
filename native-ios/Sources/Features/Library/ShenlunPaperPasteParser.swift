import Foundation

enum ShenlunPaperPasteKind: String, Hashable, Identifiable {
    case materials
    case questions

    var id: Self { self }
}

struct ShenlunPaperPasteEntry: Equatable {
    var heading: String?
    var text: String
    var instructions: String = ""
}

enum ShenlunPaperPasteParser {
    private static let materialHeading = try! NSRegularExpression(
        pattern: #"^((?:给定材料|给定资料|材料|资料)\s*[0-9０-９一二三四五六七八九十]+)(?:\s*[：:]\s*|\s+|$)(.*)$"#
    )
    private static let questionHeading = try! NSRegularExpression(
        pattern: #"^(第\s*[0-9０-９一二三四五六七八九十]+\s*题)\s*[：:、．.]?\s*(.*)$"#
    )
    private static let numberedQuestionHeading = try! NSRegularExpression(
        pattern: #"^([一二三四五六七八九十]+)[、．.]\s*(.*)$"#
    )
    private static let requirementsHeading = try! NSRegularExpression(
        pattern: #"^(?:作答)?要求\s*[：:]\s*(.*)$"#
    )

    static func parse(_ text: String, kind: ShenlunPaperPasteKind) -> [ShenlunPaperPasteEntry] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
        let sourceLines = normalized.components(separatedBy: .newlines)
        let hasExplicitQuestionBoundaries = kind == .questions && sourceLines.contains { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            return trimmed == "---" || captures(in: trimmed, using: questionHeading) != nil
        }
        let headingPattern = kind == .materials ? materialHeading
            : (hasExplicitQuestionBoundaries ? questionHeading : numberedQuestionHeading)
        var entries: [ShenlunPaperPasteEntry] = []
        var heading: String?
        var lines: [String] = []

        func finishEntry() {
            let body = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !body.isEmpty || heading != nil {
                entries.append(makeEntry(heading: heading, body: body, kind: kind))
            }
            heading = nil
            lines.removeAll(keepingCapacity: true)
        }

        for line in sourceLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "---" {
                finishEntry()
            } else if let match = captures(in: trimmed, using: headingPattern) {
                if heading != nil { finishEntry() }
                heading = match[0]
                if !match[1].isEmpty { lines.append(match[1]) }
            } else {
                lines.append(ShenlunMaterialTextFormatter.unindentedPaste(line, in: "", replacing: NSRange(location: 0, length: 0)))
            }
        }
        finishEntry()
        return entries
    }

    private static func makeEntry(heading: String?, body: String, kind: ShenlunPaperPasteKind) -> ShenlunPaperPasteEntry {
        guard kind == .questions else { return .init(heading: heading, text: body) }
        let lines = body.components(separatedBy: "\n")
        for index in lines.indices.dropFirst() {
            let line = lines[index].trimmingCharacters(in: .whitespaces)
            guard let match = captures(in: line, using: requirementsHeading) else { continue }
            let stem = lines[..<index].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            let instructions = ([match[0]] + Array(lines[(index + 1)...])).joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return .init(heading: heading, text: stem, instructions: instructions)
        }
        return .init(heading: heading, text: body)
    }

    private static func captures(in text: String, using regex: NSRegularExpression) -> [String]? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
        }
    }
}
