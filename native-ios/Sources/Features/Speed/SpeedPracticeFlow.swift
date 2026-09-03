import Foundation

enum SpeedPracticeFlow {
    /// Same questions and order, with only this attempt's answer/timing removed.
    static func retryQuestions(from questions: [SpeedQuestion]) -> [SpeedQuestion] {
        questions.filter { $0.isCorrect == false }.map { question in
            var retry = question
            retry.input = ""
            retry.isCorrect = nil
            retry.timeUsed = 0
            return retry
        }
    }

    static func canSubmit(_ question: SpeedQuestion, input: String) -> Bool {
        guard question.isCorrect == nil, let value = Double(input), value.isFinite else { return false }
        return !input.isEmpty
    }

    static func durationText(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
