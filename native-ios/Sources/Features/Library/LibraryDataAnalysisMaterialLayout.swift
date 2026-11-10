import Foundation

struct LibraryDataAnalysisMaterialParagraph: Equatable {
    let text: String
    let preservesLeadingIndent: Bool

    var usesDefaultFirstLineIndent: Bool { !text.isEmpty && !preservesLeadingIndent }
}

enum LibraryDataAnalysisMaterialLayout {
    static func paragraphs(from source: String) -> [LibraryDataAnalysisMaterialParagraph] {
        displayText(from: source)
            .components(separatedBy: "\n")
            .map { line in
                LibraryDataAnalysisMaterialParagraph(
                    text: line,
                    preservesLeadingIndent: hasExplicitLeadingIndent(line)
                )
            }
    }

    static func displayText(from source: String) -> String {
        var value = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        value = value.replacingOccurrences(
            of: "<style\\b[^>]*>[\\s\\S]*?</style>|<script\\b[^>]*>[\\s\\S]*?</script>",
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        value = value.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "</p\\s*>|</div\\s*>|</li\\s*>|</h[1-6]\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        value = value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(value)
    }

    private static func hasExplicitLeadingIndent(_ value: String) -> Bool {
        guard let first = value.unicodeScalars.first else { return false }
        return [" ", "\t", "\u{00A0}", "\u{2002}", "\u{2003}", "\u{2009}", "\u{3000}"].contains(String(first))
    }

    private static func decodeEntities(_ value: String) -> String {
        var result = ""
        var index = value.startIndex
        while index < value.endIndex {
            guard value[index] == "&",
                  let semicolon = value[index...].firstIndex(of: ";"),
                  value.distance(from: index, to: semicolon) <= 12 else {
                result.append(value[index])
                index = value.index(after: index)
                continue
            }

            let entityStart = value.index(after: index)
            let entity = String(value[entityStart..<semicolon])
            if let decoded = decodeEntity(entity) {
                result.append(decoded)
                index = value.index(after: semicolon)
            } else {
                result.append(value[index])
                index = value.index(after: index)
            }
        }
        return result
    }

    private static func decodeEntity(_ entity: String) -> String? {
        switch entity.lowercased() {
        case "nbsp": return "\u{00A0}"
        case "ensp": return "\u{2002}"
        case "emsp": return "\u{2003}"
        case "thinsp": return "\u{2009}"
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos", "#39": return "'"
        default:
            let number: UInt32?
            if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
                number = UInt32(entity.dropFirst(2), radix: 16)
            } else if entity.hasPrefix("#") {
                number = UInt32(entity.dropFirst())
            } else {
                number = nil
            }
            guard let number, let scalar = UnicodeScalar(number) else { return nil }
            return String(scalar)
        }
    }
}
