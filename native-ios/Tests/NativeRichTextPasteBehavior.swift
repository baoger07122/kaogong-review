import Foundation
#if canImport(AppKit)
import AppKit
#endif

@main
enum NativeRichTextPasteBehavior {
    static func main() {
        verifyOrdinaryLineBreaksStayPlain()
        verifyExplicitMarkdownIsConverted()
        verifyRichTextSpacingKeepsParagraphsAndBoldRuns()
        verifyParagraphSpacingInference()
        verifyAttributedInsertionAndUndo()
        verifyMarkdownTablePasteParsing()
        verifyHTMLTablePasteParsing()
    }

    private static func verifyOrdinaryLineBreaksStayPlain() {
        let plainText = "第一行\n第二行\n\n第四行"
        precondition(NativeRichTextMarkdown.htmlIfMarkdown(plainText) == nil, "ordinary line breaks and blank paragraphs must stay plain text")
    }

    private static func verifyExplicitMarkdownIsConverted() {
        let converted = NativeRichTextMarkdown.htmlIfMarkdown("**需要加粗**")
        precondition(converted?.contains("<strong>需要加粗</strong>") == true, "explicit Markdown bold should become rich text markup")
        let multiline = NativeRichTextMarkdown.htmlIfMarkdown("普通段落\n- 项目符号")
        precondition(multiline?.contains("• 项目符号") == true, "a Markdown list after an ordinary first line should still be recognized")
    }

    private static func verifyRichTextSpacingKeepsParagraphsAndBoldRuns() {
        let boldKey = NSAttributedString.Key("behavior.bold")
        let source = NSMutableAttributedString(string: "加粗内容\n\n普通内容")
        source.addAttribute(boldKey, value: true, range: NSRange(location: 0, length: 4))
        let spacious = NSMutableParagraphStyle()
        spacious.paragraphSpacing = 18
        spacious.paragraphSpacingBefore = 12
        source.addAttribute(.paragraphStyle, value: spacious, range: NSRange(location: 0, length: source.length))

        let compact = NativeRichTextPastePolicy.compactParagraphSpacing(in: source)
        precondition(compact.string == source.string, "paste spacing cleanup must keep every newline and blank paragraph")
        precondition(compact.attribute(boldKey, at: 0, effectiveRange: nil) as? Bool == true, "local bold attributes must survive spacing cleanup")
        let paragraph = compact.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        precondition(paragraph?.paragraphSpacing == NativeRichTextPastePolicy.maximumParagraphSpacing, "oversized paragraph spacing should be capped")
        precondition(paragraph?.paragraphSpacingBefore == NativeRichTextPastePolicy.maximumParagraphSpacing, "oversized paragraph leading should be capped")
    }

    private static func verifyParagraphSpacingInference() {
        let naturalKey = NativeRichTextPastePolicy.confirmedNaturalParagraph
        let headingKey = NativeRichTextPastePolicy.semanticHeadingParagraph
        let explicitKey = NativeRichTextPastePolicy.explicitParagraphSpacing

        let ordinary = NSMutableAttributedString(string: "自然段一\n自然段二")
        ordinary.addAttribute(naturalKey, value: true, range: NSRange(location: 0, length: ordinary.length))
        let ordinaryCompacted = NativeRichTextPastePolicy.compactParagraphSpacing(in: ordinary)
        let ordinaryStyle = ordinaryCompacted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        precondition(ordinaryStyle?.paragraphSpacing == NativeRichTextPastePolicy.maximumParagraphSpacing,
                     "confirmed adjacent ordinary source paragraphs should receive compact spacing")

        let heading = NSMutableAttributedString(string: "标题\n正文")
        heading.addAttribute(naturalKey, value: true, range: NSRange(location: 0, length: heading.length))
        heading.addAttribute(headingKey, value: 1, range: NSRange(location: 0, length: ("标题\n" as NSString).length))
        let headingCompacted = NativeRichTextPastePolicy.compactParagraphSpacing(in: heading)
        let headingStyle = headingCompacted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        precondition((headingStyle?.paragraphSpacing ?? 0) == 0,
                     "a semantic title must not receive inferred paragraph spacing")

        let explicitZero = NSMutableAttributedString(string: "显式零段距一\n显式零段距二")
        explicitZero.addAttribute(naturalKey, value: true, range: NSRange(location: 0, length: explicitZero.length))
        explicitZero.addAttribute(explicitKey, value: true, range: NSRange(location: 0, length: ("显式零段距一\n" as NSString).length))
        let explicitCompacted = NativeRichTextPastePolicy.compactParagraphSpacing(in: explicitZero)
        let explicitStyle = explicitCompacted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        precondition((explicitStyle?.paragraphSpacing ?? 0) == 0,
                     "source-confirmed explicit zero spacing must not be replaced by the default gap")

        // A bare newline can represent an HTML <br> or an RTF soft line break.
        // Without source paragraph metadata it must not be guessed as a paragraph boundary.
        let softBreak = NSAttributedString(string: "软换行一\n软换行二")
        let softBreakCompacted = NativeRichTextPastePolicy.compactParagraphSpacing(in: softBreak)
        let softBreakStyle = softBreakCompacted.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        precondition((softBreakStyle?.paragraphSpacing ?? 0) == 0,
                     "an unclassified soft line break must not receive inferred paragraph spacing")
    }

    private static func verifyAttributedInsertionAndUndo() {
        let existing = NSMutableAttributedString(string: "前后")
        let inserted = NSAttributedString(string: "中间\n")
        let undoManager = UndoManager()
        var selectionAfterReplace: NSRange?
        undoManager.beginUndoGrouping()
        NativeRichTextPastePolicy.replace(
            inserted,
            in: NSRange(location: 1, length: 0),
            of: existing,
            undoManager: undoManager,
            onReplacement: { range, value in selectionAfterReplace = NSRange(location: range.location + value.length, length: 0) }
        )
        undoManager.endUndoGrouping()
        precondition(existing.string == "前中间\n后", "paste should insert at the current selection and preserve line breaks")
        precondition(selectionAfterReplace == NSRange(location: 4, length: 0), "selection should move to the end of inserted text")
        undoManager.undo()
        precondition(existing.string == "前后", "undo should restore the original surrounding text")
        precondition(selectionAfterReplace == NSRange(location: 1, length: 0), "undo should restore the insertion point")
    }

    private static func verifyMarkdownTablePasteParsing() {
        let text = "前置说明\n| 词语 | 核心侧重 | 一眼判断 |\n| --- | --- | --- |\n| 通常 | 常见情况，含义较宽；这是一段较长的说明文字，需要保留并在表格单元格内换行显示。 | 搭配对象 |\n后置复盘说明"
        let tables = NativeRichTextTablePasteParser.markdownTables(in: text)
        precondition(tables.count == 1, "strict three-column Markdown table should be recognized")
        precondition(tables[0].cells.count == 2 && tables[0].cells[0] == ["词语", "核心侧重", "一眼判断"], "table headers and body rows should be retained")
        precondition(tables[0].cells[1][1].contains("保留并在表格单元格内换行显示"), "long cell text should remain complete")
        let source = text as NSString
        let prefix = source.substring(to: tables[0].range.location)
        let suffix = source.substring(from: NSMaxRange(tables[0].range))
        precondition(prefix == "前置说明\n" && suffix == "\n后置复盘说明", "prefix and suffix paragraphs should stay outside the table attachment")
        precondition(NativeRichTextTablePasteParser.markdownTables(in: "普通竖线 A | B 仍是文字").isEmpty, "ordinary vertical bars should not form a table")

        let fenced = "```text\n| A | B |\n| --- | --- |\n| x | y |\n```"
        precondition(NativeRichTextTablePasteParser.markdownTables(in: fenced).isEmpty, "tables inside code fences should remain literal text")

        let oversizedRows = ["| A | B |", "| --- | --- |"] + (0..<17).map { "| row \($0) | value |" }
        precondition(
            NativeRichTextTablePasteParser.markdownTables(in: oversizedRows.joined(separator: "\n")).isEmpty,
            "overlong tables should fall back as complete text instead of pasting a truncated table"
        )
    }

    private static func verifyHTMLTablePasteParsing() {
        let html = "<p>开头</p><table><tr><th>词语</th><th>侧重</th><th>判断</th></tr><tr><td>甲<br>乙</td><td>长说明</td><td>搭配</td></tr></table><p>结尾</p>"
        let tables = NativeRichTextTablePasteParser.htmlTables(in: html)
        precondition(tables?.count == 1, "HTML table representation should be recognized")
        precondition(tables?.first?.cells[0] == ["词语", "侧重", "判断"], "HTML headers should be preserved")
        precondition(tables?.first?.cells[1][0] == "甲\n乙", "HTML line breaks should stay inside their cell")

        let unsafe = "<table><tr><td colspan=\"2\">merged</td><td>x</td></tr><tr><td>a</td><td>b</td><td>c</td></tr></table>"
        precondition(NativeRichTextTablePasteParser.containsHTMLTable(unsafe), "unsafe HTML should still be detected as a table")
        precondition(NativeRichTextTablePasteParser.htmlTables(in: unsafe) == nil, "merged cells should use the complete plain-text fallback")
    }
}
