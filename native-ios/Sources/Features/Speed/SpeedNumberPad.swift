import SwiftUI
import UIKit

private enum SpeedKeypadPalette {
    static let panel = Color.white
    static let number = Color(red: 243 / 255.0, green: 244 / 255.0, blue: 246 / 255.0) // #F3F4F6
    static let ink = Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0) // #1F2937
    static let action = Color(red: 74 / 255.0, green: 144 / 255.0, blue: 226 / 255.0) // #4A90E2
    static let pressedNumber = Color(red: 191 / 255.0, green: 219 / 255.0, blue: 254 / 255.0) // #BFDBFE
    static let pressedAction = Color(red: 58 / 255.0, green: 122 / 255.0, blue: 199 / 255.0) // #3A7AC7
}

struct SpeedNumberPad: View {
    let metrics: SpeedKeypadMetrics
    let onPress: () -> Void
    let onKey: (String) -> Void
    let onClear: () -> Void
    let onBackspace: () -> Void
    let onSubmit: () -> Void

    private let rows = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"], ["+/-", "0", "."]]

    var body: some View {
        HStack(alignment: .top, spacing: SpeedKeypadMetrics.gap) {
            VStack(spacing: SpeedKeypadMetrics.gap) {
                ForEach(rows.indices, id: \.self) { row in
                    HStack(spacing: SpeedKeypadMetrics.gap) {
                        ForEach(rows[row], id: \.self) { key in
                            SpeedTouchKey(title: key, label: key == "+/-" ? "切换正负号" : key,
                                          onPress: onPress, action: { onKey(key) })
                                .frame(width: metrics.numberWidth, height: metrics.rowHeight)
                        }
                    }
                }
            }
            VStack(spacing: SpeedKeypadMetrics.gap) {
                SpeedTouchKey(title: "C", label: "删除上一位", isAction: true,
                              fontSize: 20, weight: .semibold, onPress: onPress, action: onBackspace)
                    .frame(width: metrics.actionWidth, height: metrics.rowHeight)
                SpeedTouchKey(symbol: "delete.backward", label: "清空答案", isAction: true,
                              fontSize: 20, weight: .semibold, onPress: onPress, action: onClear)
                    .frame(width: metrics.actionWidth, height: metrics.rowHeight)
                SpeedTouchKey(symbol: "checkmark", label: "提交答案", isAction: true,
                              fontSize: 24, weight: .bold, onPress: onPress, action: onSubmit)
                    .frame(width: metrics.actionWidth, height: metrics.confirmHeight)
            }
        }
        .padding(.horizontal, SpeedKeypadMetrics.sideInset)
        .padding(.top, SpeedKeypadMetrics.sideInset)
        .padding(.bottom, metrics.bottomInset)
        .frame(width: metrics.width, height: metrics.height, alignment: .top)
        .background(SpeedKeypadPalette.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(red: 229 / 255.0, green: 231 / 255.0, blue: 235 / 255.0)).frame(height: 0.5)
        }
    }
}

/// Direct touch tracking makes release/cancellation immediate, with no ButtonStyle fade tail.
private struct SpeedTouchKey: UIViewRepresentable {
    var title: String? = nil
    var symbol: String? = nil
    let label: String
    var isAction = false
    var fontSize: CGFloat = 24
    var weight: UIFont.Weight = .medium
    let onPress: () -> Void
    let action: () -> Void
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeUIView(context: Context) -> SpeedKeyControl { SpeedKeyControl() }

    func updateUIView(_ control: SpeedKeyControl, context: Context) {
        control.onPress = onPress
        control.action = action
        control.isEnabled = isEnabled
        control.reduceMotion = reduceMotion
        control.accessibilityLabel = label
        control.configure(title: title, symbol: symbol, font: .systemFont(ofSize: fontSize, weight: weight),
                          isAction: isAction)
    }

    static func dismantleUIView(_ control: SpeedKeyControl, coordinator: ()) {
        control.setPressed(false)
    }
}

private final class SpeedKeyControl: UIControl {
    var onPress: () -> Void = {}
    var action: () -> Void = {}
    var reduceMotion = false
    private let surface = UIView()
    private let titleLabel = UILabel()
    private let icon = UIImageView()
    private let shade = UIView()
    private var actionKey = false
    private var pressed = false

    init() {
        super.init(frame: .zero)
        isAccessibilityElement = true
        accessibilityTraits = .button
        isExclusiveTouch = true
        surface.isUserInteractionEnabled = false
        surface.layer.cornerRadius = 14
        addSubview(surface)
        surface.addSubview(titleLabel)
        surface.addSubview(icon)
        shade.backgroundColor = .black
        shade.layer.cornerRadius = 14
        surface.addSubview(shade)
        titleLabel.textAlignment = .center
        icon.contentMode = .center
        addTarget(self, action: #selector(activate), for: .touchUpInside)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Transform the visual surface only; the full key's hit region never shrinks.
        surface.bounds = CGRect(origin: .zero, size: bounds.size)
        surface.center = CGPoint(x: bounds.midX, y: bounds.midY)
        titleLabel.frame = surface.bounds
        icon.frame = surface.bounds
        shade.frame = surface.bounds
    }

    func configure(title: String?, symbol: String?, font: UIFont, isAction: Bool) {
        actionKey = isAction
        titleLabel.text = title
        titleLabel.font = font
        icon.image = symbol.flatMap { UIImage(systemName: $0, withConfiguration: UIImage.SymbolConfiguration(font: font)) }
        renderPress()
    }

    func setPressed(_ value: Bool) {
        let becamePressed = value && !pressed
        pressed = value
        renderPress()
        if becamePressed { onPress() }
    }

    private func renderPress() {
        let color = actionKey
            ? (pressed ? SpeedKeypadPalette.pressedAction : SpeedKeypadPalette.action)
            : (pressed ? SpeedKeypadPalette.pressedNumber : SpeedKeypadPalette.number)
        // No timers or interpolated colors: down is deep, up is restored in this event.
        UIView.performWithoutAnimation {
            surface.backgroundColor = UIColor(color)
            titleLabel.textColor = actionKey ? .white : UIColor(SpeedKeypadPalette.ink)
            icon.tintColor = titleLabel.textColor
            shade.alpha = pressed ? 0.14 : 0
            surface.transform = pressed && !reduceMotion
                ? CGAffineTransform(translationX: 0, y: 1).scaledBy(x: 0.93, y: 0.93) : .identity
        }
    }

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard isEnabled else { return false }
        setPressed(true)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        setPressed(bounds.contains(touch.location(in: self)))
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        let inside = touch.map { bounds.contains($0.location(in: self)) } ?? false
        setPressed(false)
        if inside && isEnabled { sendActions(for: .touchUpInside) }
    }

    override func cancelTracking(with event: UIEvent?) { setPressed(false) }

    @objc private func activate() { action() }

    override func accessibilityActivate() -> Bool {
        guard isEnabled else { return false }
        onPress()
        action()
        return true
    }
}
