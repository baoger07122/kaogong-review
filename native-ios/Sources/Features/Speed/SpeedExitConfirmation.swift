import SwiftUI

struct SpeedExitConfirmation: View {
    let onContinue: () -> Void
    let onExit: () -> Void
    var body: some View {
        NativeModalContainer {
            VStack(spacing: 14) {
                Text("退出练习").font(.system(size: 17, weight: .semibold))
                Text("当前练习进度将丢失，确定退出吗？")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Button(action: onContinue) {
                        Text("继续").frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("speed-exit-continue")
                    Button(role: .destructive, action: onExit) {
                        Text("退出").frame(maxWidth: .infinity).frame(height: 44).contentShape(Rectangle())
                    }.accessibilityIdentifier("speed-exit-confirm")
                }.buttonStyle(.plain).font(.system(size: 14, weight: .medium))
            }
        }
        .transition(.identity)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onContinue)
    }
}
