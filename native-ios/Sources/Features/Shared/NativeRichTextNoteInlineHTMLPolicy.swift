import Foundation

struct NativeRichTextNoteInlineHTMLStyle: Equatable, Sendable {
    var bold = false
    var italic = false
    var underlined = false
    var fontSize: Double?
    var link: String?
}

enum NativeRichTextNoteInlineHTMLPolicy {
    static func applying(_ style: NativeRichTextNoteInlineHTMLStyle, to html: String) -> String {
        var result = html
        if let fontSize = style.fontSize, fontSize.isFinite, fontSize > 0 {
            result = "<span style=\"font-size: \(fontSize)pt;\">\(result)</span>"
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

    private static func escapeAttribute(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
