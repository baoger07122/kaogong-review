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
        ShenlunTextView(
            text: $text,
            height: $measuredHeight,
            minimumHeight: minimumHeight,
            growsWithContent: growsWithContent
        )
        .frame(height: growsWithContent ? measuredHeight : minimumHeight)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = .systemFont(ofSize: 15)
        view.textColor = .label
        view.backgroundColor = .clear
        view.text = text
        view.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = !growsWithContent
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = growsWithContent == false
        view.setContentCompressionResistancePriority(.required, for: .vertical)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        if view.text != text {
            view.text = text
        }
        view.isScrollEnabled = !growsWithContent
        view.showsVerticalScrollIndicator = !growsWithContent
        updateHeight(view)
    }

    private func updateHeight(_ view: UITextView) {
        guard growsWithContent, view.bounds.width > 0 else { return }
        let fitting = view.sizeThatFits(
            CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)
        )
        let nextHeight = max(minimumHeight, ceil(fitting.height))
        guard abs(height - nextHeight) > 0.5 else { return }
        DispatchQueue.main.async {
            if abs(self.height - nextHeight) > 0.5 {
                self.height = nextHeight
            }
        }
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
