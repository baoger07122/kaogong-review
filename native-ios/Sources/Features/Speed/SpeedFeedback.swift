import SwiftUI

struct SpeedCorrectFlash: View {
    let trigger: Int
    @State private var opacity = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Color(red: 16 / 255.0, green: 185 / 255.0, blue: 129 / 255.0)
            .opacity(opacity).ignoresSafeArea().allowsHitTesting(false)
            .task(id: trigger) {
                guard trigger > 0, !reduceMotion else { opacity = 0; return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { opacity = 0.18 }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.28)) { opacity = 0 }
            }
    }
}

struct SpeedFeedbackMessage: Identifiable {
    let id = UUID()
    let text: String
    let success: Bool?
}
