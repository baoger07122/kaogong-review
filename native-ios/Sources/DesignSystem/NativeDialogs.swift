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
    let onClose: () -> Void
    let onSave: () -> Void
    let content: Content

    init(
        title: String,
        canSave: Bool,
        onClose: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.canSave = canSave
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

                Button("保存", action: onSave)
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

    var body: some View {
        NativeModalContainer {
            VStack(alignment: .leading, spacing: 15) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                Text(message)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button("删除", action: onDelete)
                        .buttonStyle(NativeDangerButtonStyle())
                    Button("取消", action: onCancel)
                        .buttonStyle(NativeSecondaryButtonStyle())
                }
            }
        }
    }
}
