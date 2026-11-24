import Foundation
import SwiftUI
import UIKit

struct ShenlunWorkspacePaperLayout {
    static let paperSize = CGSize(width: 612, height: 866)
    static let textSize = CGSize(width: 472, height: 741)
    static let textOrigin = CGPoint(x: 70, y: 68)

    var pages: [NSAttributedString]

    static func material(title: String, text: String) -> ShenlunWorkspacePaperLayout {
        let value = NSMutableAttributedString(string: "")
        let headerStyle = NSMutableParagraphStyle()
        headerStyle.alignment = .left
        headerStyle.paragraphSpacing = 11
        value.append(NSAttributedString(string: title + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: UIColor(red: 0.12, green: 0.29, blue: 0.47, alpha: 1),
            .paragraphStyle: headerStyle
        ]))
        value.append(NSAttributedString(string: text, attributes: bodyAttributes()))
        return paginate(value)
    }

    static func requirements(questions: [ShenlunWorkspaceQuestion]) -> ShenlunWorkspacePaperLayout {
        let value = NSMutableAttributedString(string: "")
        let titleStyle = NSMutableParagraphStyle()
        titleStyle.alignment = .left
        titleStyle.paragraphSpacing = 11
        value.append(NSAttributedString(string: "作答要求\n", attributes: [
            .font: UIFont.systemFont(ofSize: 17, weight: .semibold),
            .foregroundColor: UIColor.label,
            .paragraphStyle: titleStyle
        ]))
        if questions.isEmpty {
            value.append(NSAttributedString(string: "尚无题目。\n", attributes: bodyAttributes()))
            return paginate(value)
        }
        for question in questions {
            let number = question.originalNumber.trimmingCharacters(in: .whitespacesAndNewlines)
            var numberText = number.isEmpty ? "第 \(question.order + 1) 题" : number
            let originalText = question.title + "\n" + question.instructions
            if let score = question.fullScore, score > 0, !containsScoreMarker(originalText) {
                numberText += "（\(score.formatted(.number.precision(.fractionLength(0...2)))) 分）"
            }
            let centered = NSMutableParagraphStyle()
            centered.alignment = .center
            centered.paragraphSpacing = 3
            value.append(NSAttributedString(string: numberText + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 12, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: centered
            ]))

            let titleStyle = NSMutableParagraphStyle()
            titleStyle.alignment = .left
            titleStyle.paragraphSpacing = 2
            value.append(NSAttributedString(string: question.title + "\n", attributes: [
                .font: UIFont.systemFont(ofSize: 13, weight: .bold),
                .foregroundColor: UIColor.label,
                .paragraphStyle: titleStyle
            ]))
            let instructions = question.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            if !instructions.isEmpty {
                value.append(NSAttributedString(string: instructions + "\n", attributes: bodyAttributes()))
            }
            value.append(NSAttributedString(string: "\n", attributes: bodyAttributes()))
        }
        return paginate(value)
    }

    private static func containsScoreMarker(_ text: String) -> Bool {
        guard let expression = try? NSRegularExpression(pattern: #"\d+(?:\.\d+)?\s*分(?:值)?"#) else { return false }
        let range = NSRange(text.startIndex..., in: text)
        return expression.firstMatch(in: text, range: range) != nil
    }

    private static func bodyAttributes() -> [NSAttributedString.Key: Any] {
        let fallback = UIFont(name: "STFangsong", size: 11.31)
            ?? UIFont(name: "Songti SC", size: 11.31)
            ?? UIFont.systemFont(ofSize: 11.31)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.lineBreakMode = .byCharWrapping
        paragraph.firstLineHeadIndent = 22.63
        paragraph.minimumLineHeight = 20.6
        paragraph.maximumLineHeight = 20.6
        paragraph.paragraphSpacing = 0
        return [.font: fallback, .foregroundColor: UIColor.label, .paragraphStyle: paragraph]
    }

    private static func paginate(_ source: NSAttributedString) -> ShenlunWorkspacePaperLayout {
        guard source.length > 0 else { return ShenlunWorkspacePaperLayout(pages: [.init(string: "")]) }
        let storage = NSTextStorage(attributedString: source)
        let layoutManager = NSLayoutManager()
        storage.addLayoutManager(layoutManager)
        layoutManager.usesFontLeading = true
        var ranges: [NSRange] = []
        var pageStart = 0
        var safety = 0
        while pageStart < storage.length && safety < 500 {
            safety += 1
            let container = NSTextContainer(size: textSize)
            configure(container)
            layoutManager.addTextContainer(container)
            layoutManager.ensureLayout(for: container)
            let glyphRange = layoutManager.glyphRange(for: container)
            var characterRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
            if characterRange.location < pageStart {
                let coveredEnd = NSMaxRange(characterRange)
                characterRange = NSRange(location: pageStart, length: max(0, coveredEnd - pageStart))
            }
            guard characterRange.length > 0 else {
                characterRange = NSRange(location: pageStart, length: storage.length - pageStart)
                ranges.append(characterRange)
                break
            }
            ranges.append(characterRange)
            pageStart = NSMaxRange(characterRange)
        }
        if ranges.isEmpty { ranges = [NSRange(location: 0, length: storage.length)] }
        let text = source.string as NSString
        let pages = ranges.map { range -> NSAttributedString in
            let page = source.attributedSubstring(from: range)
            let start = NSRange(location: range.location, length: 0)
            // A page can start on a continuation line of an existing paragraph.
            guard range.location > text.paragraphRange(for: start).location,
                  let paragraph = page.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle,
                  let continuation = paragraph.mutableCopy() as? NSMutableParagraphStyle else { return page }
            continuation.firstLineHeadIndent = continuation.headIndent
            let adjusted = NSMutableAttributedString(attributedString: page)
            let firstParagraph = (page.string as NSString).paragraphRange(for: NSRange(location: 0, length: 0))
            adjusted.addAttribute(.paragraphStyle, value: continuation, range: firstParagraph)
            return adjusted
        }
        return ShenlunWorkspacePaperLayout(pages: pages)
    }

    fileprivate static func configure(_ container: NSTextContainer) {
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.size = textSize
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byCharWrapping
        container.maximumNumberOfLines = 0
    }
}

struct ShenlunWorkspaceTextPaperPage: UIViewRepresentable {
    let text: NSAttributedString

    func makeUIView(context: Context) -> UITextView {
        makeTextView()
    }

    func makeTextView() -> UITextView {
        // The paginator uses NSLayoutManager, so the reader uses the same layout engine.
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.clipsToBounds = true
        view.backgroundColor = .clear
        view.contentInsetAdjustmentBehavior = .never
        view.contentInset = .zero
        view.textContainerInset = .zero
        view.layoutManager.usesFontLeading = true
        applyPage(to: view)
        return view
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        ShenlunWorkspacePaperLayout.textSize
    }

    func updateUIView(_ view: UITextView, context: Context) {
        if view.attributedText != text { applyPage(to: view) }
    }

    private func applyPage(to view: UITextView) {
        view.attributedText = text
        ShenlunWorkspacePaperLayout.configure(view.textContainer)
        view.layoutManager.ensureLayout(for: view.textContainer)
        view.setContentOffset(.zero, animated: false)
    }
}
