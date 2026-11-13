import SwiftUI
import UIKit

/// A read-only, non-scrolling text view that keeps native text selection without
/// resetting its selection whenever the surrounding SwiftUI page refreshes.
struct LibrarySelectableQuestionText: UIViewRepresentable {
    let text: String
    let identity: String
    let font: UIFont
    let lineSpacing: CGFloat
    var foregroundColor: UIColor = .label
    var onTap: (() -> Void)? = nil
    var onInteractionStateChange: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.textContainer.lineBreakMode = .byWordWrapping
        textView.textContainer.maximumNumberOfLines = 0
        textView.contentInset = .zero
        textView.contentInsetAdjustmentBehavior = .never
        textView.setContentHuggingPriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.required, for: .vertical)
        textView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textView.delegate = context.coordinator
        context.coordinator.attach(to: textView)
        context.coordinator.applyCurrentContent()
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.applyCurrentContent()
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        let fitted = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: ceil(fitted.height))
    }

    static func dismantleUIView(_ textView: UITextView, coordinator: Coordinator) {
        textView.delegate = nil
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: LibrarySelectableQuestionText
        private weak var textView: UITextView?
        private var tapRecognizer: UITapGestureRecognizer?
        private var lastText: String?
        private var lastIdentity: String?
        private var lastFont: UIFont?
        private var lastLineSpacing: CGFloat?
        private var lastForegroundColor: UIColor?
        private var activeSelectionGestures = Set<ObjectIdentifier>()
        private var reportsActiveInteraction = false
        private var hadSelectionWhenTapBegan = false
        private var isApplyingContent = false

        init(parent: LibrarySelectableQuestionText) {
            self.parent = parent
        }

        func attach(to textView: UITextView) {
            self.textView = textView
            let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            tap.numberOfTapsRequired = 1
            tap.cancelsTouchesInView = false
            tap.delegate = self
            for recognizer in textView.gestureRecognizers ?? [] where recognizer is UILongPressGestureRecognizer {
                tap.require(toFail: recognizer)
            }
            textView.addGestureRecognizer(tap)
            tapRecognizer = tap
            for recognizer in textView.gestureRecognizers ?? [] where recognizer !== tap {
                if recognizer is UILongPressGestureRecognizer || recognizer is UIPanGestureRecognizer {
                    recognizer.addTarget(self, action: #selector(selectionGestureChanged(_:)))
                }
            }
        }

        func detach() {
            reportActiveInteraction(false)
            textView = nil
            tapRecognizer = nil
            activeSelectionGestures.removeAll()
        }

        func applyCurrentContent() {
            guard let textView else { return }
            let textChanged = lastText != parent.text
            let identityChanged = lastIdentity != parent.identity
            let styleChanged = lastFont?.isEqual(parent.font) != true
                || lastLineSpacing != parent.lineSpacing
                || lastForegroundColor?.isEqual(parent.foregroundColor) != true
            guard textChanged || identityChanged || styleChanged else { return }

            let priorSelection = textView.selectedRange
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = parent.lineSpacing
            paragraph.lineBreakMode = .byWordWrapping
            let attributes: [NSAttributedString.Key: Any] = [
                .font: parent.font,
                .foregroundColor: parent.foregroundColor,
                .paragraphStyle: paragraph
            ]
            isApplyingContent = true
            textView.attributedText = NSAttributedString(string: parent.text, attributes: attributes)
            if identityChanged {
                textView.selectedRange = NSRange(location: 0, length: 0)
                activeSelectionGestures.removeAll()
                if reportsActiveInteraction {
                    reportsActiveInteraction = false
                    let identity = parent.identity
                    DispatchQueue.main.async { [weak self] in
                        guard let self,
                              self.lastIdentity == identity,
                              !self.reportsActiveInteraction else { return }
                        self.parent.onInteractionStateChange?(false)
                    }
                }
            } else {
                let location = min(priorSelection.location, (parent.text as NSString).length)
                let length = min(priorSelection.length, (parent.text as NSString).length - location)
                textView.selectedRange = NSRange(location: location, length: length)
            }
            isApplyingContent = false
            lastText = parent.text
            lastIdentity = parent.identity
            lastFont = parent.font
            lastLineSpacing = parent.lineSpacing
            lastForegroundColor = parent.foregroundColor
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingContent else { return }
            reportActiveInteraction(textView.selectedRange.length > 0 || !activeSelectionGestures.isEmpty)
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard gestureRecognizer === tapRecognizer, let textView else { return true }
            hadSelectionWhenTapBegan = textView.selectedRange.length > 0
            return !hadSelectionWhenTapBegan
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            gestureRecognizer === tapRecognizer || otherGestureRecognizer === tapRecognizer
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended,
                  !hadSelectionWhenTapBegan,
                  let textView,
                  textView.selectedRange.length == 0 else { return }
            parent.onTap?()
        }

        @objc private func selectionGestureChanged(_ recognizer: UIGestureRecognizer) {
            let key = ObjectIdentifier(recognizer)
            switch recognizer.state {
            case .began, .changed:
                activeSelectionGestures.insert(key)
            case .ended, .cancelled, .failed:
                activeSelectionGestures.remove(key)
            default:
                break
            }
            let hasSelection = (textView?.selectedRange.length ?? 0) > 0
            reportActiveInteraction(hasSelection || !activeSelectionGestures.isEmpty)
        }

        private func reportActiveInteraction(_ active: Bool) {
            guard reportsActiveInteraction != active else { return }
            reportsActiveInteraction = active
            parent.onInteractionStateChange?(active)
        }
    }
}
