import SwiftUI
import UIKit

struct ShenlunAdaptiveTextEditor: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    let growsWithContent: Bool
    @State private var measuredHeight: CGFloat

    init(text: Binding<String>, minimumHeight: CGFloat, growsWithContent: Bool) {
        _text = text
        self.minimumHeight = minimumHeight
        self.growsWithContent = growsWithContent
        _measuredHeight = State(initialValue: minimumHeight)
    }

    var body: some View {
        GeometryReader { proxy in
            ShenlunTextView(
                text: $text,
                height: $measuredHeight,
                minimumHeight: minimumHeight,
                growsWithContent: growsWithContent,
                availableWidth: proxy.size.width
            )
        }
        .frame(height: growsWithContent ? measuredHeight : minimumHeight)
        .frame(maxWidth: .infinity)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.primary.opacity(0.11), lineWidth: 0.8)
        }
    }
}

struct ShenlunTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var height: CGFloat
    let minimumHeight: CGFloat
    let growsWithContent: Bool
    let availableWidth: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = AppTheme.inputUIFont
        view.textColor = .label
        view.backgroundColor = .clear
        view.text = text
        view.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.typingAttributes = Self.typingAttributes
        view.isScrollEnabled = !growsWithContent
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = growsWithContent == false
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.font = AppTheme.inputUIFont
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.typingAttributes = Self.typingAttributes
        if view.text != text {
            view.text = text
        }
        view.isScrollEnabled = !growsWithContent
        view.showsVerticalScrollIndicator = !growsWithContent
        updateHeight(view)
    }

    private func updateHeight(_ view: UITextView) {
        guard growsWithContent else { return }
        let width = max(1, availableWidth > 0 ? availableWidth : view.bounds.width)
        guard width > 1 else { return }
        view.layoutIfNeeded()
        let fitting = view.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let nextHeight = max(minimumHeight, ceil(fitting.height))
        guard abs(height - nextHeight) > 0.5 else { return }
        DispatchQueue.main.async {
            if abs(self.height - nextHeight) > 0.5 {
                self.height = nextHeight
            }
        }
    }

    private static var typingAttributes: [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = AppTheme.inputLineSpacing
        paragraph.lineBreakMode = .byCharWrapping
        return [
            .font: AppTheme.inputUIFont,
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: ShenlunTextView

        init(parent: ShenlunTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.updateHeight(textView)
        }
    }
}
