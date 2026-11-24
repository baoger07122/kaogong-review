import SwiftUI
import UIKit

struct ShenlunAdaptiveTextEditor: View {
    @Binding var text: String
    let minimumHeight: CGFloat
    let growsWithContent: Bool
    let fontSize: CGFloat?
    let accessibilityIdentifier: String?
    let onFormattedMaterialPaste: ((ShenlunMaterialPasteEdit) -> Void)?
    @State private var measuredHeight: CGFloat

    init(
        text: Binding<String>,
        minimumHeight: CGFloat,
        growsWithContent: Bool,
        fontSize: CGFloat? = nil,
        accessibilityIdentifier: String? = nil,
        onFormattedMaterialPaste: ((ShenlunMaterialPasteEdit) -> Void)? = nil
    ) {
        _text = text
        self.minimumHeight = minimumHeight
        self.growsWithContent = growsWithContent
        self.fontSize = fontSize
        self.accessibilityIdentifier = accessibilityIdentifier
        self.onFormattedMaterialPaste = onFormattedMaterialPaste
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
                fontSize: fontSize,
                availableWidth: width,
                accessibilityIdentifier: accessibilityIdentifier,
                onFormattedMaterialPaste: onFormattedMaterialPaste
            )
            .modifier(NativeDirectionalTextFieldNavigation())
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
    let fontSize: CGFloat?
    let availableWidth: CGFloat
    let accessibilityIdentifier: String?
    let onFormattedMaterialPaste: ((ShenlunMaterialPasteEdit) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.pasteDelegate = context.coordinator
        view.font = UIFont.systemFont(ofSize: fontSize ?? AppTheme.inputUIFont.pointSize)
        view.textColor = .label
        view.backgroundColor = .clear
        view.accessibilityIdentifier = accessibilityIdentifier
        view.text = text
        view.textContainerInset = UIEdgeInsets(top: 9, left: 9, bottom: 9, right: 9)
        view.textContainer.lineFragmentPadding = 0
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.typingAttributes = Self.typingAttributes(fontSize: fontSize)
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
        view.font = UIFont.systemFont(ofSize: fontSize ?? AppTheme.inputUIFont.pointSize)
        view.textContainer.widthTracksTextView = true
        view.textContainer.lineBreakMode = .byCharWrapping
        view.typingAttributes = Self.typingAttributes(fontSize: fontSize)
        let appliesMaterialChange = onFormattedMaterialPaste != nil && view.markedTextRange == nil
        if view.text != text, !view.isFirstResponder || appliesMaterialChange {
            let previousCaret = view.selectedRange.location
            view.text = text
            if view.isFirstResponder {
                view.selectedRange = NSRange(location: min(previousCaret, text.utf16.count), length: 0)
            }
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

    private static func typingAttributes(fontSize: CGFloat?) -> [NSAttributedString.Key: Any] {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = AppTheme.inputLineSpacing
        paragraph.lineBreakMode = .byCharWrapping
        return [
            .font: UIFont.systemFont(ofSize: fontSize ?? AppTheme.inputUIFont.pointSize),
            .foregroundColor: UIColor.label,
            .paragraphStyle: paragraph
        ]
    }

    final class Coordinator: NSObject, UITextViewDelegate, UITextPasteDelegate {
        var parent: ShenlunTextView
        private var heightMeasurementRequestID: UInt64 = 0
        private var applyingPaste = false

        init(parent: ShenlunTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !applyingPaste else { return }
            parent.text = textView.text
            parent.updateHeight(textView, coordinator: self)
        }

        func textPasteConfigurationSupporting(
            _ supporting: any UITextPasteConfigurationSupporting,
            performPasteOf attributedString: NSAttributedString,
            to textRange: UITextRange
        ) -> UITextRange {
            guard let view = supporting as? UITextView else { return textRange }
            let startOffset = view.offset(from: view.beginningOfDocument, to: textRange.start)
            let length = view.offset(from: textRange.start, to: textRange.end)
            let selection = NSRange(location: startOffset, length: length)
            let raw = attributedString.string
            let document = view.text ?? ""
            let edit = parent.onFormattedMaterialPaste == nil ? nil
                : ShenlunMaterialTextFormatter.formattedPaste(raw, in: document, replacing: selection)
            let insertion = edit?.insertion
                ?? ShenlunMaterialTextFormatter.unindentedPaste(raw, in: document, replacing: selection)

            applyingPaste = true
            view.replace(textRange, withText: insertion)
            applyingPaste = false
            if let edit, view.text == edit.formattedText, let onPaste = parent.onFormattedMaterialPaste {
                onPaste(edit)
            } else if view.text != parent.text {
                parent.text = view.text
            }
            parent.updateHeight(view, coordinator: self)

            guard let start = view.position(from: view.beginningOfDocument, offset: startOffset),
                  let end = view.position(from: start, offset: insertion.utf16.count),
                  let insertedRange = view.textRange(from: start, to: end) else { return textRange }
            view.selectedTextRange = view.textRange(from: end, to: end)
            return insertedRange
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
