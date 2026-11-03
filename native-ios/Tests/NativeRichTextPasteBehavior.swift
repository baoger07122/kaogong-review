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
        verifyAttributedInsertionAndUndo()
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
}
