import SwiftUI

struct LibraryReadingModeToggle: View {
    enum Placement: Equatable {
        case library
        case detail
    }

    @Binding var isRedoPractice: Bool
    var isEnabled = true
    var placement: Placement = .library

    var body: some View {
        Button {
            guard isEnabled else { return }
            isRedoPractice.toggle()
        } label: {
            Text(isRedoPractice ? "刷" : "看")
                .font(.system(size: placement == .detail ? 14 : 13, weight: .semibold))
                .foregroundStyle(foregroundColor)
                .frame(width: 44, height: 44)
                .background(
                    placement == .library ? Color.white : AppTheme.secondaryBackground,
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(LibraryToolbarPressStyle(highlightDiameter: 44))
        .disabled(!isEnabled)
        .accessibilityLabel(isRedoPractice ? "切换到看题模式" : "切换到刷题模式")
    }

    private var foregroundColor: Color {
        if placement == .detail || isRedoPractice {
            return AppTheme.accent
        }
        return .secondary
    }
}

struct LibraryToolbarPressStyle: ButtonStyle {
    let highlightDiameter: CGFloat

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        let pressed = isEnabled && configuration.isPressed
        return configuration.label
            .overlay {
                Circle()
                    .fill(AppTheme.accent.opacity(pressed ? 0.16 : 0))
                    .frame(width: highlightDiameter, height: highlightDiameter)
                    .allowsHitTesting(false)
            }
            .scaleEffect(pressed && !reduceMotion ? 0.9 : 1)
            .offset(y: pressed && !reduceMotion ? 1 : 0)
            .animation(pressed || reduceMotion ? nil : .easeOut(duration: 0.14), value: pressed)
    }
}
