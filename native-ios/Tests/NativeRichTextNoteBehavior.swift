import Foundation

@main
enum NativeRichTextNoteBehavior {
    static func main() throws {
        verifyInlineHTMLRoundTripKeepsMixedStyles()
        verifyCSSDerivedBoldAndMissingCSSSafety()
        try verifyTableCellBoldRangesRoundTrip()
        verifyDefaultAndExplicitParagraphSpacing()
        verifyLegacyAutomaticSpacingCleanup()
    }

    private static func verifyInlineHTMLRoundTripKeepsMixedStyles() {
        let html = NativeRichTextNoteInlineHTMLPolicy.applying(
            NativeRichTextNoteInlineHTMLStyle(bold: true, italic: true, underlined: true, fontSize: 18, link: "https://example.com/a?x=1&y=2"),
            to: "加粗文字"
        )
        precondition(html.contains("<strong>"), "bold runs must have a self-contained strong tag")
        precondition(html.contains("<em>"), "italic runs must remain explicit")
        precondition(html.contains("<u>"), "underline runs must remain explicit")
        precondition(html.contains("font-size: 18.0pt"), "heading-sized runs must preserve their point size")
        precondition(html.contains("&amp;"), "link attributes must be escaped safely")

        let linkedHTML = NativeRichTextNoteInlineHTMLPolicy.applying(
            NativeRichTextNoteInlineHTMLStyle(bold: true, link: "https://example.com/a?x=1&y=2"),
            to: "链接粗体"
        )
        precondition(linkedHTML.contains("href=\"https://example.com/a?x=1&amp;y=2\""))
        precondition(
            NativeRichTextFallbackParser.parseForEditing(linkedHTML) == nil,
            "safe fallback must keep linked documents read-only when it cannot preserve href metadata"
        )

        let unlinkedHTML = NativeRichTextNoteInlineHTMLPolicy.applying(
            NativeRichTextNoteInlineHTMLStyle(bold: true, italic: true, underlined: true, fontSize: 18),
            to: "加粗文字"
        )
        guard let runs = NativeRichTextFallbackParser.parseForEditing(unlinkedHTML),
              let styled = runs.compactMap({ run -> (String, NativeRichTextFallbackTextStyle)? in
                  if case .styledText(let value, let style) = run { return (value, style) }
                  return nil
              }).first(where: { $0.0 == "加粗文字" }) else {
            preconditionFailure("a self-contained mixed-style note fragment should remain editable")
        }
        precondition(styled.1.contains(.bold), "re-decoded note text must keep bold")
        precondition(styled.1.contains(.italic), "re-decoded note text must keep italic")
        precondition(styled.1.contains(.underline), "re-decoded note text must keep underline")
        precondition(styled.1.contains(.heading2), "re-decoded note text must keep heading-scale size")
    }

    private static func verifyCSSDerivedBoldAndMissingCSSSafety() {
        let cssStyled = "<html><head><style>.p.p1{font-weight:bold}</style></head><body><p class=\"p p1\">旧样式粗体</p></body></html>"
        guard let runs = NativeRichTextFallbackParser.parseForEditing(cssStyled),
              runs.contains(where: { run in
                  if case .styledText(let value, let style) = run {
                      return value.contains("旧样式粗体") && style.contains(.bold)
                  }
                  return false
              }) else {
            preconditionFailure("recognized CSS class bold should remain visible and losslessly editable")
        }

        let missingStyle = "<p class=\"p1\">无样式声明的旧内容</p>"
        precondition(NativeRichTextFallbackParser.parseForEditing(missingStyle) == nil, "unknown CSS classes must stay read-only instead of losing an unobservable style")
        let missingStylePreview = NativeRichTextFallbackParser.parse(missingStyle)
        precondition(!missingStylePreview.contains(where: { run in
            if case .styledText(_, let style) = run { return style.contains(.bold) }
            return false
        }), "legacy bold must not be guessed when its style declaration is absent")

        let unsupportedClass = "<style>.p1{font-weight:bold;color:red}</style><p class=\"p1\">安全回退</p>"
        precondition(NativeRichTextFallbackParser.parseForEditing(unsupportedClass) == nil, "unsupported CSS decoration must keep the original document read-only")
    }

    private static func verifyTableCellBoldRangesRoundTrip() throws {
        let range = NativeRichTextPastedBoldRange(row: 0, column: 1, location: 1, length: 2)
        var table = RichTextTable(
            cells: [["普通", "混合加粗"], ["另一格", "保留"]],
            cellBoldRanges: [range]
        )
        table.normalizeBoldRanges()
        let encoded = try JSONEncoder().encode(table)
        let decoded = try JSONDecoder().decode(RichTextTable.self, from: encoded)
        precondition(decoded.cellBoldRanges == [range], "table bold ranges must remain attached to the same cell after save and reload")
    }

    private static func verifyDefaultAndExplicitParagraphSpacing() {
        let ordinary = "<p>普通段落</p>"
        let defaultHTML = NativeRichTextNoteParagraphHTMLPolicy.applying(
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16),
            to: ordinary
        )
        precondition(defaultHTML == ordinary, "ordinary paragraphs must export without injected spacing")

        let pasted = NativeRichTextNoteParagraphHTMLPolicy.applying(
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 4, lineSpacing: 2, fontSize: 16),
            to: ordinary
        )
        precondition(
            pasted == "<p style=\"margin-bottom: 4.0pt; line-height: 18.0pt\">普通段落</p>",
            "explicit pasted spacing, already clamped to 4 pt, must remain encoded while default paragraphs stay compact"
        )
    }

    private static func verifyLegacyAutomaticSpacingCleanup() {
        let legacy = [
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 5, lineSpacing: 2, fontSize: 16),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 2, fontSize: 16)
        ]
        let cleaned = NativeRichTextNoteParagraphHTMLPolicy.removingLegacyInjectedSpacing(
            from: legacy,
            isQuoted: [false, false],
            hasContent: [true, true]
        )
        precondition(cleaned.allSatisfy { $0.spacingAfter == 0 && $0.lineSpacing == 0 },
                     "a note-wide 2 pt line-spacing pattern with legacy 5 pt inter-paragraph spacing must be cleaned in memory")

        let ambiguousSingleParagraph = [
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 2, fontSize: 16)
        ]
        let preserved = NativeRichTextNoteParagraphHTMLPolicy.removingLegacyInjectedSpacing(
            from: ambiguousSingleParagraph,
            isQuoted: [false],
            hasContent: [true]
        )
        precondition(preserved == ambiguousSingleParagraph,
                     "an isolated 2 pt style without evidence of automatic injection must remain intact")

        let explicitPasted = [
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 4, lineSpacing: 3, fontSize: 16),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16)
        ]
        precondition(
            NativeRichTextNoteParagraphHTMLPolicy.removingLegacyInjectedSpacing(
                from: explicitPasted,
                isQuoted: [false, false],
                hasContent: [true, true]
            ) == explicitPasted,
            "explicit pasted spacing at or below the 4 pt cap must be preserved"
        )
    }
}
