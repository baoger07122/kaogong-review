import SwiftUI

/// A new trigger cancels the previous reset, including the very first digit's animation.
struct SpeedInputPulse: ViewModifier {
    let trigger: Int
    var duration = 0.09
    var initialScale = 0.8
    @State private var scale = 1.0
    @State private var opacity = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.scaleEffect(scale).opacity(opacity)
            .task(id: trigger) {
                guard trigger > 0, !reduceMotion else { scale = 1; opacity = 1; return }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { scale = initialScale; opacity = 0.4 }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: duration)) { scale = 1; opacity = 1 }
            }
    }
}

struct SpeedQuestionEntrance: ViewModifier {
    let questionID: String
    @State private var visible = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : 10)
            .task(id: questionID) {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { visible = false }
                do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.32)) { visible = true }
            }
    }
}

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
