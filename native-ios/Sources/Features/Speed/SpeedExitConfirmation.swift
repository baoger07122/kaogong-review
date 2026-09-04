import SwiftUI

struct SpeedExitConfirmation: View {
    let onContinue: () -> Void
    let onExit: () -> Void

    var body: some View {
        NativeConfirmationDialog(
            title: "退出练习",
            message: "当前练习进度将丢失，确定退出吗？",
            confirmTitle: "退出",
            cancelTitle: "继续",
            confirmIdentifier: "speed-exit-confirm",
            cancelIdentifier: "speed-exit-continue",
            onConfirm: onExit,
            onCancel: onContinue,
            isDanger: true
        )
    }
}
