import SwiftUI

struct NativeModalContainer<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.20)
                .ignoresSafeArea()
            content
                .padding(20)
                .frame(maxWidth: 420)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: AppTheme.modalRadius, style: .continuous)
                )
                .shadow(color: .black.opacity(0.16), radius: 28, y: 12)
                .padding(24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}

struct NativeEditorDialog<Content: View>: View {
    let title: String
    let canSave: Bool
    let actionTitle: String
    let onClose: () -> Void
    let onSave: () -> Void
    let content: Content

    init(
        title: String,
        canSave: Bool,
        actionTitle: String = "保存",
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.canSave = canSave
        self.actionTitle = actionTitle
        self.onClose = onClose
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NativeModalContainer {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(title)
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.07), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                content

                Button(actionTitle, action: onSave)
                    .buttonStyle(NativePrimaryButtonStyle())
                    .frame(maxWidth: 210)
                    .frame(maxWidth: .infinity)
                    .disabled(!canSave)
            }
        }
    }
}

struct NativeDeleteDialog: View {
    let title: String
    let message: String
    let onDelete: () -> Void
    let onCancel: () -> Void
    var actionTitle = "删除"

    var body: some View {
        NativeModalContainer {
            VStack(alignment: .leading, spacing: 15) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(actionTitle, action: onDelete)
                        .buttonStyle(NativeDangerButtonStyle())
                    Button("取消", action: onCancel)
                        .buttonStyle(NativeSecondaryButtonStyle())
                }
            }
        }
    }
}

/// Shared, immediate confirmation surface for short destructive decisions.
///
/// Unlike editor sheets, confirmation dialogs use an opaque card and no material
/// transition so the dimming layer and dialog become visible in the same frame.
struct NativeConfirmationDialog: View {
    let title: String
    let message: String
    let confirmTitle: String
    let cancelTitle: String
    let confirmIdentifier: String
    let cancelIdentifier: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    var isDanger = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.30)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(message)
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 18)

                Divider()

                HStack(spacing: 0) {
                    confirmationButton(
                        cancelTitle,
                        color: .secondary,
                        identifier: cancelIdentifier,
                        action: onCancel
                    )

                    Divider().frame(height: 48)

                    confirmationButton(
                        confirmTitle,
                        color: isDanger ? AppTheme.danger : AppTheme.accent,
                        identifier: confirmIdentifier,
                        action: onConfirm
                    )
                }
                .frame(height: 48)
            }
            .frame(maxWidth: 320)
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: Color(red: 0.13, green: 0.19, blue: 0.35).opacity(0.18), radius: 24, y: 12)
            .padding(.horizontal, 32)
        }
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onCancel)
    }

    private func confirmationButton(
        _ title: String,
        color: Color,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(color)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(NativeConfirmationButtonStyle())
        .accessibilityIdentifier(identifier)
    }
}

private struct NativeConfirmationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(configuration.isPressed ? 0.07 : 0))
    }
}
