import Foundation

struct NativeRichTextNoteListHTMLItem: Equatable, Sendable {
    var contentHTML: String
    var marker: String
    var level: Int
    var firstLineHeadIndent: Double
    var headIndent: Double
}

enum NativeRichTextNoteListHTMLPolicy {
    private struct ListFrame {
        var tag: String
        var level: Int
        var nextNumber: Int
        var markerType: String
    }

    private struct TagToken {
        var name: String
        var closing: Bool
        var attributes: String
        var range: NSRange
    }

    static func items(in html: String) -> [NativeRichTextNoteListHTMLItem] {
        guard let expression = try? NSRegularExpression(pattern: #"(?is)<\s*(/?)\s*(ul|ol|li)\b([^>]*)>"#) else { return [] }
        let source = html as NSString
        let tokens = expression.matches(in: html, range: NSRange(location: 0, length: source.length)).map { match in
            TagToken(
                name: source.substring(with: match.range(at: 2)).lowercased(),
                closing: match.range(at: 1).length > 0,
                attributes: source.substring(with: match.range(at: 3)),
                range: match.range
            )
        }

        var listStack: [ListFrame] = []
        var result: [NativeRichTextNoteListHTMLItem] = []
        for index in tokens.indices {
            let token = tokens[index]
            if token.name == "ul" || token.name == "ol" {
                if token.closing {
                    if let matching = listStack.lastIndex(where: { $0.tag == token.name }) {
                        listStack.removeSubrange(matching...)
                    }
                } else {
                    let level = listStack.count
                    let start = max(1, integerAttribute("start", in: token.attributes) ?? 1)
                    listStack.append(ListFrame(
                        tag: token.name,
                        level: level,
                        nextNumber: start - 1,
                        markerType: stringAttribute("type", in: token.attributes) ?? ""
                    ))
                }
                continue
            }
            guard token.name == "li", !token.closing, !listStack.isEmpty,
                  let closingIndex = matchingListItemEnd(from: index, tokens: tokens) else { continue }

            var frame = listStack.removeLast()
            frame.nextNumber += 1
            listStack.append(frame)
            let contentStart = NSMaxRange(token.range)
            let contentEnd = tokens[closingIndex].range.location
            guard contentEnd >= contentStart else { continue }
            let content = directListItemHTML(
                source: source,
                tokens: tokens,
                openingIndex: index,
                closingIndex: closingIndex,
                contentStart: contentStart,
                contentEnd: contentEnd
            )
            guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            result.append(NativeRichTextNoteListHTMLItem(
                contentHTML: content,
                marker: marker(for: frame),
                level: frame.level,
                firstLineHeadIndent: Double(frame.level * 18),
                headIndent: Double((frame.level + 1) * 18)
            ))
        }
        return result
    }

    private static func matchingListItemEnd(from index: Int, tokens: [TagToken]) -> Int? {
        var depth = 1
        guard index + 1 < tokens.count else { return nil }
        for candidate in (index + 1)..<tokens.count where tokens[candidate].name == "li" {
            if tokens[candidate].closing {
                depth -= 1
                if depth == 0 { return candidate }
            } else {
                depth += 1
            }
        }
        return nil
    }

    private static func directListItemHTML(
        source: NSString,
        tokens: [TagToken],
        openingIndex: Int,
        closingIndex: Int,
        contentStart: Int,
        contentEnd: Int
    ) -> String {
        guard contentEnd >= contentStart else { return "" }
        var output = ""
        var cursor = contentStart
        var nestedListDepth = 0
        var encounteredNestedList = false
        if openingIndex + 1 < closingIndex {
            for index in (openingIndex + 1)..<closingIndex where tokens[index].name == "ul" || tokens[index].name == "ol" {
                let token = tokens[index]
                if !token.closing {
                    encounteredNestedList = true
                    if nestedListDepth == 0, token.range.location > cursor {
                        output += source.substring(with: NSRange(location: cursor, length: token.range.location - cursor))
                    }
                    nestedListDepth += 1
                } else if nestedListDepth > 0 {
                    nestedListDepth -= 1
                    if nestedListDepth == 0 { cursor = NSMaxRange(token.range) }
                }
            }
        }
        if !encounteredNestedList, contentEnd >= cursor {
            output += source.substring(with: NSRange(location: cursor, length: contentEnd - cursor))
        }
        return output
    }

    private static func marker(for frame: ListFrame) -> String {
        guard frame.tag == "ol" else {
            switch frame.markerType.lowercased() {
            case "circle": return "◦ "
            case "square": return "▪ "
            default: return "• "
            }
        }
        switch frame.markerType {
        case "a": return "\(alphabetic(frame.nextNumber, uppercase: false)). "
        case "A": return "\(alphabetic(frame.nextNumber, uppercase: true)). "
        case "i": return "\(roman(frame.nextNumber).lowercased()). "
        case "I": return "\(roman(frame.nextNumber)). "
        default: return "\(frame.nextNumber). "
        }
    }

    private static func integerAttribute(_ name: String, in attributes: String) -> Int? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(pattern: #"(?i)\b"# + escaped + #"\s*=\s*[\"']?(-?\d+)"#),
              let match = expression.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: attributes) else { return nil }
        return Int(attributes[range])
    }

    private static func stringAttribute(_ name: String, in attributes: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        guard let expression = try? NSRegularExpression(pattern: #"(?i)\b"# + escaped + #"\s*=\s*[\"']?([^\s\"'>]+)"#),
              let match = expression.firstMatch(in: attributes, range: NSRange(attributes.startIndex..., in: attributes)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: attributes) else { return nil }
        return String(attributes[range])
    }

    private static func alphabetic(_ number: Int, uppercase: Bool) -> String {
        guard number > 0 else { return String(number) }
        var value = number
        var result = ""
        while value > 0 {
            value -= 1
            let scalar = UnicodeScalar((uppercase ? 65 : 97) + (value % 26))!
            result = String(scalar) + result
            value /= 26
        }
        return result
    }

    private static func roman(_ number: Int) -> String {
        guard (1...3999).contains(number) else { return String(number) }
        let values: [(Int, String)] = [(1000, "M"), (900, "CM"), (500, "D"), (400, "CD"), (100, "C"), (90, "XC"), (50, "L"), (40, "XL"), (10, "X"), (9, "IX"), (5, "V"), (4, "IV"), (1, "I")]
        var remaining = number
        var result = ""
        for (value, symbol) in values {
            while remaining >= value {
                result += symbol
                remaining -= value
            }
        }
        return result
    }
}
