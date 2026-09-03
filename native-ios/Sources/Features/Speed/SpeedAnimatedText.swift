import SwiftUI
import UIKit

enum SpeedTextMotion: Equatable {
    case answer(Int)
    case expression(String)

    var isAnswer: Bool { if case .answer = self { return true }; return false }
    var shouldAnimate: Bool { if case .answer(let revision) = self { return revision > 0 }; return true }
}

/// Commit text and its animation in one UIKit update, never in a delayed SwiftUI task.
struct SpeedAnimatedText: UIViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let nightMode: Bool
    let motion: SpeedTextMotion
    var kerning: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> SpeedTextSurface { SpeedTextSurface() }
    func updateUIView(_ view: SpeedTextSurface, context: Context) {
        view.update(text: text, fontSize: fontSize, nightMode: nightMode,
                    motion: motion, kerning: kerning, reduceMotion: reduceMotion)
    }
    static func dismantleUIView(_ view: SpeedTextSurface, coordinator: ()) { view.cancelMotion() }
}

final class SpeedTextSurface: UIView {
    private let surface = UIView()
    private let scroll = UIScrollView()
    private let label = UILabel()
    private let underline = UIView()
    private var previousMotion: SpeedTextMotion?
    private var previousText = ""
    private var answer = false
    private var scrollToEnd = false
    private var pendingMotion: SpeedTextMotion?

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        addSubview(surface)
        surface.addSubview(scroll)
        surface.addSubview(underline)
        scroll.addSubview(label)
        scroll.showsHorizontalScrollIndicator = false
        scroll.showsVerticalScrollIndicator = false
        scroll.bounces = false
        label.textAlignment = .center
        isAccessibilityElement = false // The containing SwiftUI equation supplies one stable label.
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func update(text: String, fontSize: CGFloat, nightMode: Bool, motion: SpeedTextMotion,
                kerning: CGFloat, reduceMotion: Bool) {
        let changed = previousMotion != motion
        let textChanged = previousText != text
        if changed || textChanged || reduceMotion {
            cancelMotion()
            pendingMotion = changed && motion.shouldAnimate && !reduceMotion ? motion : nil
        }
        answer = motion.isAnswer
        let color = nightMode ? UIColor(white: 245 / 255.0, alpha: 1)
            : UIColor(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0, alpha: 1)
        UIView.performWithoutAnimation {
            label.attributedText = NSAttributedString(string: text, attributes: [
                .font: answer ? UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
                    : UIFont.systemFont(ofSize: fontSize, weight: .regular),
                .foregroundColor: color, .kern: kerning
            ])
            underline.isHidden = !answer
            underline.backgroundColor = color.withAlphaComponent(nightMode ? 0.4 : 0.32)
            scroll.isScrollEnabled = answer
            scrollToEnd = scrollToEnd || textChanged
        }
        previousMotion = motion
        previousText = text
        setNeedsLayout()
        layoutIfNeeded()
    }

    private func startPendingMotion() {
        // A first input may arrive before SwiftUI has assigned the new answer bounds.
        // Start only after text, underline and the animation pivot have real geometry.
        guard window != nil, bounds.width > 0, bounds.height > 0,
              let motion = pendingMotion else { return }
        pendingMotion = nil
        let answer = motion.isAnswer
        let duration = answer ? 0.15 : 0.32
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = answer ? 0.4 : 0
        fade.toValue = 1
        fade.duration = duration
        let movement = CABasicAnimation(keyPath: answer ? "transform.scale" : "transform.translation.y")
        movement.fromValue = answer ? 0.8 : 10
        movement.toValue = answer ? 1 : 0
        movement.duration = duration
        let group = CAAnimationGroup()
        group.animations = [fade, movement]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0, 0, 0.58, 1)
        // One key replaces any previous pulse, including rapid repeated taps.
        surface.layer.add(group, forKey: "web-text-motion")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Keep layout separate from the animated transform; never set its frame.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        surface.bounds = CGRect(origin: .zero, size: bounds.size)
        surface.center = CGPoint(x: bounds.midX, y: bounds.midY)
        scroll.frame = surface.bounds
        let textWidth = ceil(label.attributedText?.size().width ?? 0)
        let width = max(max(0, bounds.width - (answer ? 4 : 0)), textWidth)
        label.frame = CGRect(x: answer ? 2 : 0, y: 0, width: width, height: bounds.height)
        scroll.contentSize = CGSize(width: width + (answer ? 4 : 0), height: bounds.height)
        underline.frame = CGRect(x: 0, y: max(0, bounds.height - 2.5), width: bounds.width, height: 2.5)
        if scrollToEnd {
            scroll.setContentOffset(CGPoint(x: max(0, scroll.contentSize.width - bounds.width), y: 0), animated: false)
            scrollToEnd = false
        }
        CATransaction.commit()
        startPendingMotion()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil { setNeedsLayout() } else { cancelMotion() }
    }

    func cancelMotion() {
        pendingMotion = nil
        surface.layer.removeAnimation(forKey: "web-text-motion")
    }
}
