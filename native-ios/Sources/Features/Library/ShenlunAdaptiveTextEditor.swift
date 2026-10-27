import SwiftUI
import UIKit

struct ShenlunAdaptiveTextEditor: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    let growsWithContent: Bool
    let accessibilityIdentifier: String?
    @State private var measuredHeight: CGFloat

    init(
        text: Binding<String>,
        minimumHeight: CGFloat,
        growsWithContent: Bool,
        accessibilityIdentifier: String? = nil
    ) {
        _text = text
        self.minimumHeight = minimumHeight
        self.growsWithContent = growsWithContent
        self.accessibilityIdentifier = accessibilityIdentifier
        _measuredHeight = State(initialValue: minimumHeight)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(0, proxy.size.width)
            ShenlunTextView(
                text: $text,
                height: $measuredHeight,
                minimumHeight: minimumHeight,
                growsWithContent: growsWithContent,
                availableWidth: width,
                accessibilityIdentifier: accessibilityIdentifier
            )
            .frame(width: width, alignment: .leading)
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
    let accessibilityIdentifier: String?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.font = AppTheme.inputUIFont
        view.textColor = .label
        view.backgroundColor = .clear
        view.accessibilityIdentifier = accessibilityIdentifier
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
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        view.accessibilityIdentifier = accessibilityIdentifier
        view.font = AppTheme.inputUIFont
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.typingAttributes = Self.typingAttributes
        if view.text != text, !view.isFirstResponder {
            view.text = text
        }
        view.isScrollEnabled = !growsWithContent
        view.showsVerticalScrollIndicator = !growsWithContent
        updateHeight(view, coordinator: context.coordinator)
    }

    private func updateHeight(_ view: UITextView, coordinator: Coordinator) {
        let requestID = coordinator.beginHeightMeasurement()
        guard growsWithContent, availableWidth.isFinite, availableWidth > 1 else { return }
        let width = availableWidth
        view.layoutIfNeeded()
        let fitting = view.sizeThatFits(
            CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        let nextHeight = max(minimumHeight, ceil(fitting.height))
        coordinator.publishMeasuredHeight(
            nextHeight,
            width: width,
            text: view.text ?? "",
            requestID: requestID
        )
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
        private var heightMeasurementRequestID: UInt64 = 0

        init(parent: ShenlunTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            parent.updateHeight(textView, coordinator: self)
        }

        func beginHeightMeasurement() -> UInt64 {
            heightMeasurementRequestID &+= 1
            return heightMeasurementRequestID
        }

        func publishMeasuredHeight(_ value: CGFloat, width: CGFloat, text: String, requestID: UInt64) {
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.heightMeasurementRequestID == requestID,
                      abs(self.parent.availableWidth - width) <= 0.5,
                      self.parent.text == text,
                      abs(self.parent.height - value) > 0.5 else { return }
                self.parent.height = value
            }
        }
    }
}
