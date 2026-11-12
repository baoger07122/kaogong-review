import SwiftUI

struct LibraryReadingModeToggle: View {
    @Binding var isRedoPractice: Bool
    var isEnabled = true

    var body: some View {
        Button {
            guard isEnabled else { return }
            isRedoPractice.toggle()
        } label: {
            Text(isRedoPractice ? "刷题" : "看题")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isRedoPractice ? AppTheme.accent : Color.primary.opacity(0.76))
                .frame(width: 54, height: 44)
                .background(
                    isRedoPractice ? AppTheme.accent.opacity(0.11) : AppTheme.secondaryBackground,
                    in: Capsule()
                )
                .contentShape(Capsule())
        }
        .buttonStyle(LibraryReadingModeToggleStyle())
        .disabled(!isEnabled)
        .accessibilityLabel(isRedoPractice ? "切换到看题模式" : "切换到刷题模式")
    }
}

private struct LibraryReadingModeToggleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? -0.045 : 0)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }
}
