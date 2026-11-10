import SwiftUI
import UIKit

struct LibraryDataAnalysisMaterialText: UIViewRepresentable {
    let source: String
    var fontSize: CGFloat = 14.5
    var lineSpacing: CGFloat = AppTheme.questionLineSpacing

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.accessibilityLabel = "资料分析材料"
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        view.attributedText = makeAttributedText()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: measured.height)
    }

    private func makeAttributedText() -> NSAttributedString {
        let paragraphs = LibraryDataAnalysisMaterialLayout.paragraphs(from: source)
        let text = paragraphs.map(\.text).joined(separator: "\n")
        let font = UIFont.systemFont(ofSize: fontSize)
        let result = NSMutableAttributedString(
            string: text,
            attributes: [.font: font, .foregroundColor: UIColor.label]
        )
        var location = 0
        for (index, paragraph) in paragraphs.enumerated() {
            let length = paragraph.text.utf16.count + (index < paragraphs.count - 1 ? 1 : 0)
            let style = NSMutableParagraphStyle()
            style.headIndent = 0
            style.firstLineHeadIndent = paragraph.usesDefaultFirstLineIndent ? font.pointSize * 2 : 0
            style.lineSpacing = lineSpacing
            if length > 0 {
                result.addAttribute(.paragraphStyle, value: style, range: NSRange(location: location, length: length))
            }
            location += length
        }
        return result
    }
}
