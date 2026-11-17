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
        .buttonStyle(LibraryReadingModeToggleStyle())
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

private struct LibraryReadingModeToggleStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.93 : 1)
            .background {
                if configuration.isPressed {
                    Circle().fill(AppTheme.accent.opacity(0.08))
                }
            }
            .brightness(configuration.isPressed ? -0.045 : 0)
            .animation(.easeOut(duration: configuration.isPressed ? 0.08 : 0.16), value: configuration.isPressed)
    }
}
