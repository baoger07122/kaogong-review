import Foundation

@main
enum NativeRichTextNoteBehavior {
    static func main() throws {
        verifyInlineHTMLRoundTripKeepsMixedStyles()
        verifyInlineHTMLTextEscapingAndColor()
        verifyAppExportedNoteRemainsEditable()
        verifyCSSDerivedBoldAndMissingCSSSafety()
        try verifyTableCellBoldRangesRoundTrip()
        verifyTableStructureEditsRemapFormatting()
        try verifyFlowchartRoundTrip()
        verifyDefaultAndExplicitParagraphSpacing()
        verifyParagraphIndentRoundTripMetadata()
        verifyVersionedParagraphLayoutMetadata()
        verifyNoteBlockMetadataRoundTrip()
        verifyPastedParagraphSpacingPolicy()
        verifyExactParagraphPairing()
        verifyListHTMLRecovery()
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
        guard let linkedRuns = NativeRichTextFallbackParser.parseForEditing(linkedHTML),
              case let .styledText(_, linkedStyle)? = linkedRuns.first else {
            preconditionFailure("the editor's HTTPS links must remain editable")
        }
        precondition(linkedStyle.link?.absoluteString == "https://example.com/a?x=1&y=2")
        precondition(linkedStyle.contains(.bold))
        precondition(NativeRichTextFallbackParser.parseForEditing("<a href=\"javascript:alert(1)\">链接</a>") == nil)

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

    private static func verifyAppExportedNoteRemainsEditable() {
        let inline = NativeRichTextNoteInlineHTMLPolicy.applying(
            NativeRichTextNoteInlineHTMLStyle(bold: true, fontSize: 18, colorHex: "#2A7BCD"),
            to: "理由<br>补充"
        )
        let paragraph = NativeRichTextNoteParagraphHTMLPolicy.applying(
            NativeRichTextNoteParagraphHTMLStyle(
                spacingBefore: 4, spacingAfter: 8, lineSpacing: 3, fontSize: 18,
                firstLineHeadIndent: 18, headIndent: 12
            ),
            to: "<p>\(inline)</p>"
        )
        let html = paragraph + "<p><br></p><p>下一段</p>"
        guard let runs = NativeRichTextFallbackParser.parseForEditing(html),
              case let .styledText(styled, style)? = runs.first else {
            preconditionFailure("a note using the app's paragraph and inline styles must remain editable")
        }
        precondition(styled == "理由\u{2028}补充")
        precondition(style.pointSize == 18 && style.color == 0x2A7BCD && style.contains(.bold))
        let text = runs.compactMap { run -> String? in
            switch run {
            case .text(let value), .styledText(let value, _): value
            default: nil
            }
        }.joined()
        precondition(text == "理由\u{2028}补充\n\n下一段\n")
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

    private static func verifyInlineHTMLTextEscapingAndColor() {
        let escaped = NativeRichTextNoteInlineHTMLPolicy.escapingText(" 设计 <方式>  ", preservingSpaces: true)
        precondition(escaped == "&nbsp;设计 &lt;方式&gt;&nbsp;&nbsp;", "inline serialization must preserve edge spaces while escaping text")
        let softBreak = NativeRichTextNoteInlineHTMLPolicy.escapingText("前\u{2028}后")
        precondition(softBreak == "前<br>后", "a soft line break must remain inside its paragraph")

        let colored = NativeRichTextNoteInlineHTMLPolicy.applying(
            NativeRichTextNoteInlineHTMLStyle(bold: true, colorHex: "#2A7BCD"),
            to: "设计方式"
        )
        precondition(colored == "<strong><span style=\"color: #2A7BCD;\">设计方式</span></strong>", "foreground color and bold must remain inline")
        precondition(!colored.contains("<p"), "inline styling must not introduce a nested paragraph block")
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

    private static func verifyTableStructureEditsRemapFormatting() {
        var table = RichTextTable(
            cells: [["项目", "解释"], ["一", "正文加粗"], ["二", "释义"]],
            cellBoldRanges: [
                NativeRichTextPastedBoldRange(row: 1, column: 1, location: 2, length: 2),
                NativeRichTextPastedBoldRange(row: 2, column: 1, location: 0, length: 2)
            ]
        )
        table.replaceText(at: .init(row: 1, column: 1), with: "改后的加粗")
        precondition(table.cellBoldRanges?.first?.location == 3, "edited prefix must move the unchanged bold suffix")
        let inserted = table.apply(.addRow, at: .init(row: 1, column: 1))
        precondition(inserted == RichTextTable.Cell(row: 2, column: 1) && table.cells[2] == ["", ""])
        _ = table.apply(.removeColumn, at: .init(row: 3, column: 0))
        precondition(table.cells == [["解释"], ["改后的加粗"], [""], ["释义"]])
        precondition(table.cellBoldRanges?.map(\.row) == [1, 3] && table.cellBoldRanges?.map(\.column) == [0, 0],
                     "inserting in the middle and deleting the first column must retain the bold cell identities")
        precondition(table.apply(.removeColumn, at: .init(row: 2, column: 0)) == nil,
                     "a table must retain its last column")
        precondition(!table.isFlowchart)
    }

    private static func verifyFlowchartRoundTrip() throws {
        var block = RichTextTable.flowchart()
        block.replaceText(at: .init(row: 0, column: 0), with: "阅读材料")
        block.replaceText(at: .init(row: 0, column: 1), with: "圈画关键信息")
        block.replaceText(at: .init(row: 1, column: 0), with: "梳理层次")
        let moved = block.apply(.moveUp, at: .init(row: 1, column: 0))
        precondition(moved == RichTextTable.Cell(row: 0, column: 0))
        let data = try JSONEncoder().encode(block)
        let marker = "[[NATIVE_TABLE:\(data.base64EncodedString())]]"
        let parsed = NativeRichTextFallbackParser.parseForEditing("<p>复盘</p><p>\(marker)</p><p>总结</p>")
        guard let runs = parsed,
              let attachment = runs.first(where: { if case .tableWithMarker = $0 { return true }
                  return false }),
              case let .tableWithMarker(encoded, originalMarker) = attachment,
              let recovered = Data(base64Encoded: encoded) else {
            preconditionFailure("mixed notes must retain the flowchart marker in the safe parser")
        }
        let decoded = try JSONDecoder().decode(RichTextTable.self, from: recovered)
        precondition(originalMarker == marker && decoded == block && decoded.isFlowchart)
        precondition(decoded.plainText() == "梳理层次\n\n阅读材料\n圈画关键信息")
        precondition(!decoded.canApply(.addColumn, at: .init(row: 0, column: 0)))
        let oldTable = RichTextTable()
        let oldData = try JSONEncoder().encode(oldTable)
        let decodedOldTable = try JSONDecoder().decode(RichTextTable.self, from: oldData)
        precondition(decodedOldTable == oldTable && !decodedOldTable.isFlowchart,
                     "a table without a presentation field must still decode as a table")
    }

    private static func verifyDefaultAndExplicitParagraphSpacing() {
        let ordinary = "<p>普通段落</p>"
        let defaultHTML = NativeRichTextNoteParagraphHTMLPolicy.applying(
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16),
            to: ordinary
        )
        precondition(
            defaultHTML == "<p data-note-layout-version=\"1\" data-note-spacing-before=\"0.0\" data-note-spacing-after=\"0.0\" data-note-line-spacing=\"0.0\">普通段落</p>",
            "ordinary paragraphs must export explicit zero-valued layout metadata without injecting visual spacing"
        )

        let pasted = NativeRichTextNoteParagraphHTMLPolicy.applying(
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 4, lineSpacing: 2, fontSize: 16),
            to: ordinary
        )
        precondition(
            pasted == "<p style=\"margin-bottom: 4.0pt\" data-note-layout-version=\"1\" data-note-spacing-before=\"0.0\" data-note-spacing-after=\"4.0\" data-note-line-spacing=\"2.0\">普通段落</p>",
            "pasted paragraph spacing and line spacing must use app metadata instead of fixed CSS line height"
        )
    }

    private static func verifyVersionedParagraphLayoutMetadata() {
        let style = NativeRichTextNoteParagraphHTMLStyle(
            spacingBefore: 0,
            spacingAfter: 4,
            lineSpacing: 2,
            fontSize: 16,
            firstLineHeadIndent: 24,
            headIndent: 12,
            tailIndent: -8
        )
        let html = NativeRichTextNoteParagraphHTMLPolicy.applying(style, to: "<p>冷读段落</p>")
        let metadata = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: html)
        precondition(metadata.count == 1, "each saved paragraph must have one metadata row")
        guard let restored = metadata[0].versionedLayout else {
            preconditionFailure("new paragraph metadata must decode")
        }
        precondition(restored == style, "cold reads must recover zero and nonzero paragraph spacing exactly")
        precondition(metadata[0].hasExplicitSpacing, "versioned zero values count as explicit spacing")
        precondition(!html.contains("line-height:"), "saved line spacing must not depend on a fixed CSS height")

        let external = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: "<p style=\"margin-top: 2pt; margin-bottom: 5px\">来源段落</p>")
        precondition(external.count == 1 && external[0].hasExplicitSpacing, "inline HTML margins must be recognized as explicit spacing")
        precondition(external[0].cssSpacing == .some(NativeRichTextNoteParagraphHTMLSpacing(before: 2, after: 3.75)), "CSS pt and px margins must map to point spacing")
    }

    private static func verifyNoteBlockMetadataRoundTrip() {
        let style = NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 8, spacingAfter: 8, lineSpacing: 0, fontSize: 16)
        let kinds: [NativeRichTextNoteBlockKind?] = [nil, .quote, .callout, .calloutQuote, .divider]
        let html = kinds.enumerated().map { index, kind in
            NativeRichTextNoteParagraphHTMLPolicy.applying(
                style, to: "<p>\(index)</p>", blockKind: kind, isListItem: index == 0
            )
        }.joined()
        let metadata = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: html)
        precondition(metadata.map(\.blockKind) == kinds)
        precondition(metadata.map(\.isListItem) == [true, false, false, false, false])
        precondition(metadata.allSatisfy { $0.versionedLayout == style })
        let legacy = NativeRichTextNoteParagraphHTMLPolicy.metadata(in: "<blockquote><p>旧引用</p></blockquote>")
        precondition(legacy.count == 1 && legacy[0].blockKind == nil && legacy[0].isListItem == nil)
    }

    private static func verifyPastedParagraphSpacingPolicy() {
        let defaults = [
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16)
        ]
        let emptyMetadata: [NativeRichTextNoteParagraphHTMLMetadata?] = [nil, nil]
        let ordinary = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            defaults,
            hasContent: [true, true],
            isQuoted: [false, false],
            isList: [false, false],
            preservesParagraphLayout: [false, false],
            metadata: emptyMetadata,
            hasStructuredParagraphs: true
        )
        precondition(ordinary.map(\.spacingAfter) == [4, 0], "adjacent ordinary paragraphs must receive one 4 pt gap")
        precondition(ordinary.map(\.spacingBefore) == [0, 0], "the inter-paragraph gap must be applied only once")
        precondition(ordinary.map(\.lineSpacing) == [1, 1], "structured rich paragraphs must use 1 pt extra line spacing by default")

        let explicit = [
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 2, lineSpacing: 3, fontSize: 16),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 3, spacingAfter: 0, lineSpacing: 0, fontSize: 16)
        ]
        let explicitMetadata = [
            NativeRichTextNoteParagraphHTMLMetadata(tagName: "p", headingLevel: nil, versionedLayout: nil, hasExplicitSpacing: true),
            NativeRichTextNoteParagraphHTMLMetadata(tagName: "p", headingLevel: nil, versionedLayout: nil, hasExplicitSpacing: true)
        ]
        let merged = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            explicit,
            hasContent: [true, true],
            isQuoted: [false, false],
            isList: [false, false],
            preservesParagraphLayout: [false, false],
            metadata: explicitMetadata,
            hasStructuredParagraphs: true
        )
        precondition(merged.map(\.spacingAfter) == [4, 0], "source spacing on both sides must merge and cap at 4 pt")
        precondition(merged.map(\.lineSpacing) == [1, 1], "source extra line spacing must be clamped to 0–1 pt")

        let withBlank = [defaults[0], defaults[0], defaults[0]]
        let blank = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            withBlank,
            hasContent: [true, false, true],
            isQuoted: [false, false, false],
            isList: [false, false, false],
            preservesParagraphLayout: [false, false, false],
            metadata: [nil, nil, nil],
            hasStructuredParagraphs: true
        )
        precondition(blank[0].spacingAfter == 0 && blank[2].spacingBefore == 0, "a user-inserted blank paragraph must suppress automatic spacing on its sides")
        precondition(blank[1] == withBlank[1], "the explicit blank paragraph's own layout must remain untouched")

        let special = [
            defaults[0],
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 1, fontSize: 12),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 0, spacingAfter: 0, lineSpacing: 0, fontSize: 16),
            NativeRichTextNoteParagraphHTMLStyle(spacingBefore: 2, spacingAfter: 3, lineSpacing: 3, fontSize: 16)
        ]
        let protected = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            special,
            hasContent: [true, true, true, true],
            isQuoted: [false, true, false, false],
            isList: [false, false, true, false],
            preservesParagraphLayout: [false, false, false, true],
            metadata: [nil, nil, nil, nil],
            hasStructuredParagraphs: true
        )
        precondition(protected[1].spacingAfter == 5, "quotes must retain the app's 5 pt spacing")
        precondition(protected[2].lineSpacing == 0 && protected[2].spacingAfter == 0, "list items must keep their compact spacing")
        precondition(protected[3] == special[3], "table and attachment paragraph layout must remain unchanged")

        let savedStyle = defaults[0]
        let savedMetadata = NativeRichTextNoteParagraphHTMLMetadata(
            tagName: "p",
            headingLevel: nil,
            versionedLayout: savedStyle,
            hasExplicitSpacing: true
        )
        let saved = NativeRichTextNoteParagraphHTMLPolicy.normalizingPastedStyles(
            [savedStyle, savedStyle],
            hasContent: [true, true],
            isQuoted: [false, false],
            isList: [false, false],
            preservesParagraphLayout: [false, false],
            metadata: [savedMetadata, savedMetadata],
            hasStructuredParagraphs: true
        )
        precondition(saved.map(\.spacingAfter) == [0, 0], "versioned explicit zero spacing must not be mistaken for missing source spacing")
        precondition(saved.map(\.lineSpacing) == [0, 0], "saved metadata must bypass paste defaults and legacy cleanup")
    }

    private static func verifyExactParagraphPairing() {
        precondition(
            NativeRichTextNoteParagraphHTMLPolicy.paragraphsMatch(["第一段", "重复", "重复"], ["第一段", "重复", "重复"]),
            "same-format companion text must pair paragraph by paragraph in order"
        )
        precondition(
            !NativeRichTextNoteParagraphHTMLPolicy.paragraphsMatch(["第一段", "重复", "重复"], ["第一段", "重复"]),
            "missing paragraphs must not be filled by length or duplicate-name matching"
        )
        precondition(
            !NativeRichTextNoteParagraphHTMLPolicy.paragraphsMatch(["第一段", "第二段"], ["第二段", "第一段"]),
            "reordered source paragraphs must not transfer formatting onto different content"
        )
    }

    private static func verifyParagraphIndentRoundTripMetadata() {
        let source = "<p>首行和续行缩进</p>"
        let style = NativeRichTextNoteParagraphHTMLStyle(
            spacingBefore: 0,
            spacingAfter: 0,
            lineSpacing: 0,
            fontSize: 16,
            firstLineHeadIndent: 36,
            headIndent: 18,
            tailIndent: -12
        )
        let html = NativeRichTextNoteParagraphHTMLPolicy.applying(style, to: source)
        let indents = NativeRichTextNoteParagraphHTMLPolicy.indents(in: html)
        precondition(indents == [NativeRichTextNoteParagraphHTMLIndent(firstLineHeadIndent: 36, headIndent: 18, tailIndent: -12)], "saved paragraph indentation metadata must restore all three UIKit values")
        precondition(html.contains("margin-left: 18.0pt"), "hanging continuation indentation must have a readable HTML representation")
        precondition(html.contains("text-indent: 18.0pt"), "first-line indentation must have a readable HTML representation")
        precondition(html.contains("margin-right: 12.0pt"), "tail indentation must have a readable HTML representation")
        precondition(NativeRichTextNoteParagraphHTMLPolicy.indents(in: "<p>legacy</p>") == [nil], "old paragraphs without explicit metadata must remain unchanged")
    }

    private static func verifyListHTMLRecovery() {
        let unordered = NativeRichTextNoteListHTMLPolicy.items(in: "<ul><li><strong>比比皆是</strong>：到处都是</li><li>巍然挺立：高大直立</li></ul>")
        precondition(unordered.map(\.marker) == ["• ", "• "], "unordered list items must recover one visible marker each")
        precondition(unordered.map(\.contentHTML) == ["<strong>比比皆是</strong>：到处都是", "巍然挺立：高大直立"], "inline formatting must stay inside each list item")
        precondition(unordered.map(\.headIndent) == [18.0, 18.0], "wrapped list lines must share the text continuation indent")

        let nestedOrdered = NativeRichTextNoteListHTMLPolicy.items(in: "<ol type=\"A\" start=\"3\"><li>父项<ul><li>子项</li></ul></li><li>下一项</li></ol>")
        precondition(nestedOrdered.map(\.marker) == ["C. ", "• ", "D. "], "ordered and nested markers must preserve numbering and order")
        precondition(nestedOrdered.map(\.level) == [0, 1, 0], "nested list depth must be retained")
        precondition(nestedOrdered.map(\.contentHTML) == ["父项", "子项", "下一项"], "nested content must not be folded into its parent item")
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
