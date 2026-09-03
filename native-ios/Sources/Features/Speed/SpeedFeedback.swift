import SwiftUI
import UIKit

/// This view belongs behind the practice content, never above text or the keyboard.
struct SpeedCorrectFlash: UIViewRepresentable {
    let trigger: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> SpeedFlashSurface { SpeedFlashSurface() }
    func updateUIView(_ view: SpeedFlashSurface, context: Context) { view.update(trigger: trigger, reduceMotion: reduceMotion) }
}

final class SpeedFlashSurface: UIView {
    private var previousTrigger = 0
    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        backgroundColor = UIColor(red: 16 / 255.0, green: 185 / 255.0, blue: 129 / 255.0, alpha: 1)
        layer.opacity = 0
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func update(trigger: Int, reduceMotion: Bool) {
        guard trigger != previousTrigger || reduceMotion else { return }
        previousTrigger = trigger
        layer.removeAnimation(forKey: "correct-background")
        guard trigger > 0, !reduceMotion else { return }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = 0.18
        fade.toValue = 0
        fade.duration = 0.28
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: "correct-background")
    }
}

struct SpeedFeedbackToast: UIViewRepresentable {
    let message: SpeedFeedbackMessage
    let nightMode: Bool
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> SpeedToastSurface { SpeedToastSurface() }
    func updateUIView(_ view: SpeedToastSurface, context: Context) {
        view.update(message: message, dark: nightMode || colorScheme == .dark, reduceMotion: reduceMotion)
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: SpeedToastSurface, context: Context) -> CGSize? {
        CGSize(width: min(proposal.width ?? .infinity, uiView.intrinsicContentSize.width), height: 36)
    }
}

final class SpeedToastSurface: UIView {
    private let label = UILabel()
    private var previousID: UUID?
    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.textAlignment = .center
        addSubview(label)
        layer.cornerRadius = 18
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.12
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: 4)
        layer.opacity = 0 // Remain hidden after the CSS-equivalent exit finishes.
        isAccessibilityElement = true
        accessibilityIdentifier = "speed-feedback"
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var intrinsicContentSize: CGSize { CGSize(width: ceil(label.intrinsicContentSize.width) + 40, height: 36) }
    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds.insetBy(dx: 20, dy: 10)
    }
    func update(message: SpeedFeedbackMessage, dark: Bool, reduceMotion: Bool) {
        label.text = message.text
        accessibilityLabel = message.text
        backgroundColor = message.success == true
            ? UIColor(red: 52 / 255.0, green: 199 / 255.0, blue: 89 / 255.0, alpha: 1) // #34C759
            : message.success == false
                ? UIColor(red: 1, green: (dark ? 69 : 59) / 255.0, blue: (dark ? 58 : 48) / 255.0, alpha: 1) // #FF453A / #FF3B30
                : UIColor(white: 29 / 255.0, alpha: 1)
        invalidateIntrinsicContentSize()
        guard previousID != message.id else { return }
        previousID = message.id
        layer.removeAnimation(forKey: "web-toast")
        let opacity = CAKeyframeAnimation(keyPath: "opacity")
        opacity.values = [0, 1, 1, 0, 0]
        opacity.keyTimes = [0, 0.12, 0.8, 0.92, 1] // 300ms in; exit at 2s; removed at 2.5s.
        opacity.timingFunctions = Array(repeating: CAMediaTimingFunction(controlPoints: 0.25, 0.1, 0.25, 1), count: 4)
        let movement = CAKeyframeAnimation(keyPath: "transform.translation.y")
        movement.values = [-10, 0, 0, -10, -10]
        movement.keyTimes = opacity.keyTimes
        movement.timingFunctions = opacity.timingFunctions
        let group = CAAnimationGroup()
        group.animations = reduceMotion ? [opacity] : [opacity, movement]
        group.duration = 2.5
        layer.add(group, forKey: "web-toast")
    }
}

struct SpeedFeedbackMessage: Identifiable {
    let id = UUID()
    let text: String
    let success: Bool?
}
