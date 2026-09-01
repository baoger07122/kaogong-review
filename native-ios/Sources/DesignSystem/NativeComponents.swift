import SwiftUI

struct NativePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.actionFont)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                AppTheme.accent.opacity(configuration.isPressed ? 0.76 : 1),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

struct NativeSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.actionFont)
            .foregroundStyle(AppTheme.accent)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                AppTheme.accent.opacity(configuration.isPressed ? 0.16 : 0.09),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(isEnabled ? 1 : 0.38)
    }
}

struct NativeDangerButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppTheme.actionFont)
            .foregroundStyle(AppTheme.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                AppTheme.danger.opacity(configuration.isPressed ? 0.16 : 0.09),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct NativePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct NativeTextFieldStyle: TextFieldStyle {
    var isError = false

    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(AppTheme.inputFont)
            .padding(.horizontal, 12)
            .frame(height: 44)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    .stroke(
                        isError ? AppTheme.danger : Color.primary.opacity(0.08),
                        lineWidth: isError ? 1.2 : 0.6
                    )
            }
    }
}

struct NativeFieldLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(AppTheme.fieldLabelFont)
            .foregroundStyle(.secondary)
    }
}

struct NativePropertyRow: View {
    let title: String
    let value: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(value)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(
                Color.primary.opacity(0.045),
                in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
            )
        }
        .buttonStyle(.plain)
    }
}

struct NativeStatusCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let color: Color
    var isLoading = false
    var minimumHeight: CGFloat = 0

    var body: some View {
        VStack(spacing: 10) {
            if isLoading {
                ProgressView().controlSize(.large)
            } else {
                Image(systemName: systemImage)
                    .font(.system(size: 32))
                    .foregroundStyle(color)
            }
            Text(title)
                .font(AppTheme.cardTitleFont)
            Text(detail)
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: minimumHeight)
        .padding(.vertical, 28)
        .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.09), lineWidth: 0.8)
        }
    }
}

struct NativeToast: View {
    let message: String
    var systemImage = "checkmark.circle.fill"

    var body: some View {
        Label(message, systemImage: systemImage)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.82), in: Capsule())
    }
}
