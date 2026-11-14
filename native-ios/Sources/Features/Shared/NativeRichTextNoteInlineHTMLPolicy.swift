import Foundation

struct NativeRichTextNoteInlineHTMLStyle: Equatable, Sendable {
    var bold = false
    var italic = false
    var underlined = false
    var fontSize: Double?
    var colorHex: String?
    var link: String?
}

enum NativeRichTextNoteInlineHTMLPolicy {
    static func applying(_ style: NativeRichTextNoteInlineHTMLStyle, to html: String) -> String {
        var result = html
        var spanDeclarations: [String] = []
        if let fontSize = style.fontSize, fontSize.isFinite, fontSize > 0 {
            spanDeclarations.append("font-size: \(fontSize)pt")
        }
        if let colorHex = style.colorHex,
           colorHex.range(of: #"^#[0-9A-Fa-f]{6}$"#, options: .regularExpression) != nil {
            spanDeclarations.append("color: \(colorHex)")
        }
        if !spanDeclarations.isEmpty {
            result = "<span style=\"\(spanDeclarations.joined(separator: "; "));\">\(result)</span>"
        }
        if let link = style.link,
           !link.isEmpty,
           !result.localizedCaseInsensitiveContains("<a ") {
            result = "<a href=\"\(escapeAttribute(link))\">\(result)</a>"
        }
        if style.underlined { result = "<u>\(result)</u>" }
        if style.italic { result = "<em>\(result)</em>" }
        if style.bold { result = "<strong>\(result)</strong>" }
        return result
    }

    static func escapingText(
        _ value: String,
        preservingSpaces: Bool = false,
        preserveLeadingSpace: Bool? = nil,
        preserveTrailingSpace: Bool? = nil
    ) -> String {
        let scalars = Array(value.unicodeScalars)
        let preserveLeading = preserveLeadingSpace ?? preservingSpaces
        let preserveTrailing = preserveTrailingSpace ?? preservingSpaces
        return scalars.indices.map { index in
            let scalar = scalars[index]
            switch scalar.value {
            case 38: return "&amp;"
            case 60: return "&lt;"
            case 62: return "&gt;"
            case 34: return "&quot;"
            case 39: return "&#39;"
            case 9: return "&#9;"
            case 32:
                let repeated = (index > scalars.startIndex && scalars[index - 1].value == 32)
                    || (index + 1 < scalars.endIndex && scalars[index + 1].value == 32)
                return (preserveLeading && index == scalars.startIndex)
                    || (preserveTrailing && index + 1 == scalars.endIndex)
                    || (preservingSpaces && repeated)
                    ? "&nbsp;"
                    : " "
            case 0x2028: return "<br>"
            default: return String(scalar)
            }
        }.joined()
    }

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
