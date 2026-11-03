import Foundation

enum NativeRichTextMarkdown {
    static func htmlIfMarkdown(_ plainText: String) -> String? {
        isMarkdown(plainText) ? html(from: plainText) : nil
    }

    static func isMarkdown(_ value: String) -> Bool {
        let text = value.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return false }

        let blockPatterns = [
            #"^#{1,4}\s+\S"#,
            #"^[-*]\s+\S"#,
            #"^\d+\.\s+\S"#,
            #"^>\s?\S"#,
            #"^```"#,
            #"^---+$"#
        ]
        let inlinePatterns = [
            #"\*\*\S(?:.*?\S)?\*\*"#,
            #"~~\S(?:.*?\S)?~~"#,
            #"`[^`\n]+`"#,
            #"\[[^\]]+\]\([^)]+\)"#
        ]
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let hasBlockMarkdown = lines.contains { line in
            blockPatterns.contains { line.range(of: $0, options: .regularExpression) != nil }
        }
        return hasBlockMarkdown || inlinePatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    static func html(from markdown: String) -> String {
        var output: [String] = []
        var codeLines: [String] = []
        var inCode = false
        for rawLine in markdown.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n") {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if inCode {
                    output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>")
                    codeLines = []
                }
                inCode.toggle()
                continue
            }
            if inCode { codeLines.append(rawLine); continue }
            if trimmed.isEmpty { output.append("<p><br></p>"); continue }
            if trimmed == "---" { output.append("<p style=\"color:#999;font-size:10px\">────────────────</p>"); continue }
            if let heading = trimmed.range(of: #"^#{1,4}\s+"#, options: .regularExpression) {
                let level = min(2, trimmed[heading].filter { $0 == "#" }.count)
                output.append("<h\(level)>\(inline(String(trimmed[heading.upperBound...])))</h\(level)>")
                continue
            }
            if let item = trimmed.range(of: #"^[-*]\s+\[[ xX]\]\s+"#, options: .regularExpression) {
                let checked = trimmed[item].lowercased().contains("[x]")
                output.append("<p>\(checked ? "☑" : "☐") \(inline(String(trimmed[item.upperBound...])))</p>")
                continue
            }
            if let item = trimmed.range(of: #"^[-*]\s+"#, options: .regularExpression) {
                output.append("<p>• \(inline(String(trimmed[item.upperBound...])))</p>")
                continue
            }
            if trimmed.range(of: #"^\d+\.\s+"#, options: .regularExpression) != nil {
                output.append("<p>\(inline(trimmed))</p>")
                continue
            }
            if let quote = trimmed.range(of: #"^>\s?"#, options: .regularExpression) {
                output.append("<blockquote>\(inline(String(trimmed[quote.upperBound...])))</blockquote>")
                continue
            }
            output.append("<p>\(inline(rawLine))</p>")
        }
        if inCode { output.append("<pre><code>\(escape(codeLines.joined(separator: "\n")))</code></pre>") }
        return output.joined()
    }

    private static func inline(_ value: String) -> String {
        var result = escape(value)
        let replacements = [
            (#"\[([^\]]+)\]\(([^)]+)\)"#, #"<a href="$2">$1</a>"#),
            (#"\*\*(.+?)\*\*"#, #"<strong>$1</strong>"#),
            (#"~~(.+?)~~"#, #"<del>$1</del>"#),
            (#"`([^`]+)`"#, #"<code>$1</code>"#),
            (#"(?<!\*)\*([^*]+)\*(?!\*)"#, #"<em>$1</em>"#)
        ]
        for (pattern, replacement) in replacements {
            result = result.replacingOccurrences(of: pattern, with: replacement, options: .regularExpression)
        }
        return result
    }

    private static func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
