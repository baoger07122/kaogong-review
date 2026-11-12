import SwiftUI
import UIKit
import ObjectiveC

/// Adds boundary-aware arrow-key navigation to the focused native text input.
/// Normal cursor movement, text selection, and IME marked text remain owned by UIKit.
struct NativeDirectionalTextFieldNavigation: ViewModifier {
    func body(content: Content) -> some View {
        content.onKeyPress(
            keys: [.leftArrow, .rightArrow, .upArrow, .downArrow],
            phases: [.down]
        ) { press in
            NativeDirectionalTextInputRouter.handle(press)
        }
    }
}

@MainActor
private enum NativeDirectionalTextInputRouter {
    private enum Direction: Equatable {
        case left, right, up, down
    }

    private struct Field {
        let view: UIView
        let input: UITextInput
        let id: String
        let frame: CGRect

        var centerX: CGFloat { frame.midX }
        var centerY: CGFloat { frame.midY }
    }

    private static var fieldIdentityKey: UInt8 = 0

    static func handle(_ press: KeyPress) -> KeyPress.Result {
        let direction: Direction
        switch press.key {
        case .leftArrow: direction = .left
        case .rightArrow: direction = .right
        case .upArrow: direction = .up
        case .downArrow: direction = .down
        default: return .ignored
        }

        let navigationModifiers: EventModifiers = [.shift, .option, .command, .control]
        guard press.modifiers.intersection(navigationModifiers).isEmpty,
              let active = firstResponderField(),
              active.input.markedTextRange == nil,
              let selection = active.input.selectedTextRange,
              selection.isEmpty
        else { return .ignored }

        let startOffset = active.input.offset(
            from: active.input.beginningOfDocument,
            to: selection.start
        )
        let endOffset = active.input.offset(
            from: active.input.beginningOfDocument,
            to: active.input.endOfDocument
        )

        switch direction {
        case .left:
            guard startOffset == 0 else { return .ignored }
            move(from: active, direction: .left)
            return .handled
        case .right:
            guard startOffset == endOffset else { return .ignored }
            move(from: active, direction: .right)
            return .handled
        case .up, .down:
            guard isAtVerticalBoundary(active, direction: direction) else { return .ignored }
            move(from: active, direction: direction)
            return .handled
        }
    }

    private static func move(from active: Field, direction: Direction) {
        guard let window = active.view.window,
              let controller = owningViewController(for: active.view),
              let rows = rows(around: active, in: controller.view, window: window),
              let currentRow = rows.firstIndex(where: { $0.contains(where: { $0.id == active.id }) })
        else { return }

        let target: Field?
        switch direction {
        case .left, .right:
            let ordered = rows.flatMap { $0 }
            guard let index = ordered.firstIndex(where: { $0.id == active.id }) else { return }
            let targetIndex = direction == .left ? index - 1 : index + 1
            target = ordered.indices.contains(targetIndex) ? ordered[targetIndex] : nil
        case .up, .down:
            let targetRowIndex = direction == .up ? currentRow - 1 : currentRow + 1
            guard rows.indices.contains(targetRowIndex) else { return }
            target = rows[targetRowIndex].min {
                let lhsDistance = abs($0.centerX - active.centerX)
                let rhsDistance = abs($1.centerX - active.centerX)
                if abs(lhsDistance - rhsDistance) > 0.5 { return lhsDistance < rhsDistance }
                return $0.frame.minX < $1.frame.minX
            }
        }

        guard let target else { return }
        guard target.view.becomeFirstResponder() else { return }
        setCaret(in: target.input, toEnd: direction == .left || direction == .up)
        scrollIntoView(target.view)
    }

    private static func setCaret(in input: UITextInput, toEnd: Bool) {
        let position = toEnd ? input.endOfDocument : input.beginningOfDocument
        input.selectedTextRange = input.textRange(from: position, to: position)
    }

    private static func isAtVerticalBoundary(_ field: Field, direction: Direction) -> Bool {
        guard let textView = field.view as? UITextView else {
            // A single-line input has one visual line, so its up/down keys move
            // between the adjacent visual rows in the form.
            return field.view is UITextField
        }
        guard let selection = textView.selectedTextRange,
              let window = textView.window
        else { return false }

        let caret = textView.caretRect(for: selection.start)
        let textInsets = textView.textContainerInset
        let visibleContentRect = textView.bounds.inset(by: UIEdgeInsets(
            top: max(textView.contentInset.top, textInsets.top),
            left: max(textView.contentInset.left, textInsets.left),
            bottom: max(textView.contentInset.bottom, textInsets.bottom),
            right: max(textView.contentInset.right, textInsets.right)
        ))
        let caretInWindow = textView.convert(caret, to: window)
        let visibleInWindow = textView.convert(visibleContentRect, to: window)
        let lineHeight = max(1, caret.height)

        switch direction {
        case .up:
            return caretInWindow.minY <= visibleInWindow.minY + lineHeight * 0.55
        case .down:
            return caretInWindow.maxY >= visibleInWindow.maxY - lineHeight * 0.55
        case .left, .right:
            return false
        }
    }

    private static func firstResponderField() -> Field? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .filter { $0.isKeyWindow }

        for window in windows {
            if let firstResponder = firstResponder(in: window),
               let field = makeField(firstResponder, window: window) {
                return field
            }
        }
        return nil
    }

    private static func firstResponder(in view: UIView) -> UIView? {
        if (view is UITextField || view is UITextView), view.isFirstResponder { return view }
        for child in view.subviews {
            if let match = firstResponder(in: child) { return match }
        }
        return nil
    }

    private static func rows(around active: Field, in root: UIView, window: UIWindow) -> [[Field]]? {
        guard let activeController = owningViewController(for: active.view) else { return nil }
        let candidates = inputViews(in: root)
            .compactMap { makeField($0, window: window) }
            .filter { owningViewController(for: $0.view) === activeController }
            .filter { isVisibleAndEditable($0.view) }

        // Keep navigation within the nearest scroll container that has at least
        // two editable inputs. This separates most forms, lists, and presented editors.
        var scopedCandidates = candidates
        var ancestor = active.view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                let contained = candidates.filter { $0.view.isDescendant(of: scrollView) }
                if contained.count > 1 {
                    scopedCandidates = contained
                    break
                }
            }
            ancestor = current.superview
        }
        guard scopedCandidates.contains(where: { $0.id == active.id }) else { return nil }

        let sorted = scopedCandidates.sorted {
            if abs($0.frame.minY - $1.frame.minY) > 8 { return $0.frame.minY < $1.frame.minY }
            if abs($0.frame.minX - $1.frame.minX) > 1 { return $0.frame.minX < $1.frame.minX }
            return $0.id < $1.id
        }
        var rows: [[Field]] = []
        var rowAnchors: [CGFloat] = []
        for field in sorted {
            if let rowIndex = rowAnchors.indices.last(where: { abs(rowAnchors[$0] - field.frame.minY) <= 8 }) {
                rows[rowIndex].append(field)
            } else {
                rows.append([field])
                rowAnchors.append(field.frame.minY)
            }
        }
        return rows.map { $0.sorted { $0.frame.minX == $1.frame.minX ? $0.id < $1.id : $0.frame.minX < $1.frame.minX } }
    }

    private static func inputViews(in root: UIView) -> [UIView] {
        var result: [UIView] = []
        if root is UITextField || root is UITextView { result.append(root) }
        for child in root.subviews { result.append(contentsOf: inputViews(in: child)) }
        return result
    }

    private static func makeField(_ view: UIView, window: UIWindow) -> Field? {
        guard view.window === window,
              let input = view as? UITextInput,
              view is UITextField || view is UITextView,
              let id = stableID(for: view)
        else { return nil }
        let rect = view.convert(view.bounds, to: window)
        return Field(view: view, input: input, id: id, frame: rect)
    }

    private static func stableID(for view: UIView) -> String? {
        if let identifier = objc_getAssociatedObject(view, &fieldIdentityKey) as? String {
            return identifier
        }
        let identifier = "native-text-input-\(UUID().uuidString)"
        objc_setAssociatedObject(view, &fieldIdentityKey, identifier, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        return identifier
    }

    private static func isVisibleAndEditable(_ view: UIView) -> Bool {
        if let textField = view as? UITextField, !textField.isEnabled { return false }
        if let textView = view as? UITextView, !textView.isEditable { return false }
        var current: UIView? = view
        while let ancestor = current {
            guard !ancestor.isHidden,
                  ancestor.alpha > 0.01,
                  ancestor.isUserInteractionEnabled
            else { return false }
            current = ancestor.superview
        }
        return !view.bounds.isEmpty
    }

    private static func owningViewController(for view: UIView) -> UIViewController? {
        var responder: UIResponder? = view
        while let current = responder {
            if let controller = current as? UIViewController { return controller }
            responder = current.next
        }
        return nil
    }

    private static func scrollIntoView(_ view: UIView) {
        var ancestor = view.superview
        while let current = ancestor {
            if let scrollView = current as? UIScrollView {
                let rect = view.convert(view.bounds, to: scrollView).insetBy(dx: 0, dy: -8)
                scrollView.scrollRectToVisible(rect, animated: false)
            }
            ancestor = current.superview
        }
    }
}
