import Foundation
import SwiftUI

enum StickyTextPresentation {
    static func preview(_ source: String) -> String {
        guard !source.isEmpty else { return "" }
        let displaySource = NativeRichTextMarkdown.htmlIfMarkdown(source) ?? source
        return displaySource
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?is)<(style|script|head)\b[^>]*>[\s\S]*?</\1\s*>"#,
                with: "",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"(?s)/\*.*?\*/"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?m)(?:^|\s)[.#]?[a-zA-Z][^{}\n]{0,100}\{[^}]*\}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<\s*(br|/p|/div|/li|/h[1-6]|/blockquote|/section|/article)\b[^>]*>"#, with: "\n", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<\s*(p|div|li|h[1-6]|blockquote|section|article)\b[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .newlines)
            .map { line in
                line.replacingOccurrences(of: #"[\t ]+"#, with: " ", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .joined(separator: "\n")
            .replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func containsRichText(_ source: String) -> Bool {
        source.range(of: #"(?is)<(?:[a-z][^>]*|/\s*[a-z][^>]*)>"#, options: .regularExpression) != nil
            || source.contains("<!-- native-")
            || NativeRichTextMarkdown.isMarkdown(source)
    }
}

struct StickyCardSurface<Content: View, HeaderAccessory: View>: View {
    let sticky: HomeSticky
    var isEditing = false
    @ViewBuilder let content: Content
    @ViewBuilder let headerAccessory: HeaderAccessory

    init(
        sticky: HomeSticky,
        isEditing: Bool = false,
        @ViewBuilder content: () -> Content,
        @ViewBuilder headerAccessory: () -> HeaderAccessory
    ) {
        self.sticky = sticky
        self.isEditing = isEditing
        self.content = content()
        self.headerAccessory = headerAccessory()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if sticky.isPinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(AppTheme.warning)
                }
                Spacer(minLength: 0)
                headerAccessory
            }

            content

            if !sticky.tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(sticky.tag)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.60), in: Capsule())
            }

            HStack {
                Spacer()
                Text(HomeRecordRepository.chineseDate(sticky.createdAt, includeYear: false))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(homeHex: sticky.colorHex), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isEditing ? AppTheme.accent.opacity(0.48) : Color.primary.opacity(0.06), lineWidth: isEditing ? 1.2 : 0.6)
        }
    }
}
