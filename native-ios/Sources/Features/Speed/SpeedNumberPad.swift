import SwiftUI

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
                            Button { onKey(key) } label: {
                                Text(key).font(.system(size: 24, weight: .medium))
                                    .frame(width: metrics.numberWidth, height: metrics.rowHeight)
                            }
                            .buttonStyle(SpeedNumberPadButtonStyle(isAction: false, onPress: onPress))
                            .accessibilityLabel(key == "+/-" ? "切换正负号" : key)
                        }
                    }
                }
            }
            VStack(spacing: SpeedKeypadMetrics.gap) {
                Button(action: onBackspace) {
                    Text("C").font(.system(size: 20, weight: .semibold))
                        .frame(width: metrics.actionWidth, height: metrics.rowHeight)
                }.accessibilityLabel("删除上一位")
                Button(action: onClear) {
                    Image(systemName: "delete.backward").font(.system(size: 20, weight: .semibold))
                        .frame(width: metrics.actionWidth, height: metrics.rowHeight)
                }.accessibilityLabel("清空答案")
                Button(action: onSubmit) {
                    Image(systemName: "checkmark").font(.system(size: 24, weight: .bold))
                        .frame(width: metrics.actionWidth, height: metrics.confirmHeight)
                }
                .accessibilityLabel("提交答案")
            }
            .buttonStyle(SpeedNumberPadButtonStyle(isAction: true, onPress: onPress))
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

private struct SpeedNumberPadButtonStyle: ButtonStyle {
    let isAction: Bool
    let onPress: () -> Void
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(isAction ? Color.white : SpeedKeypadPalette.ink)
            .background(
                isAction
                    ? (configuration.isPressed ? SpeedKeypadPalette.pressedAction : SpeedKeypadPalette.action)
                    : (configuration.isPressed ? SpeedKeypadPalette.pressedNumber : SpeedKeypadPalette.number),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .contentShape(Rectangle())
            // Immediate, deep touch-down feedback. Only release animates (70ms), no bounce.
            .colorMultiply(Color(white: configuration.isPressed ? 0.82 : 1))
            .animation(configuration.isPressed ? nil : .easeOut(duration: 0.07)) { view in
                view.scaleEffect(configuration.isPressed ? 0.93 : 1)
                    .offset(y: configuration.isPressed ? 1 : 0)
            }
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { onPress() }
            }
    }
}
