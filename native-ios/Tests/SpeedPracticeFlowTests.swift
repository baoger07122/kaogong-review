import Foundation

@main
struct SpeedPracticeFlowTests {
    static func main() {
        let fresh = SpeedQuestion(id: "a", type: .add3, expression: "100 + 200", answer: 300)
        for input in ["", ".", "-", "NaN", "inf"] {
            precondition(!SpeedPracticeFlow.canSubmit(fresh, input: input))
        }
        for input in ["300", "0", "-2", ".5"] {
            precondition(SpeedPracticeFlow.canSubmit(fresh, input: input))
        }
        var right = fresh
        right.input = "300"; right.isCorrect = true; right.timeUsed = 1.2
        var wrong = SpeedQuestion(id: "b", type: .sub3, expression: "200 - 100", answer: 100)
        wrong.input = "50"; wrong.isCorrect = false; wrong.timeUsed = 2.3
        precondition(!SpeedPracticeFlow.canSubmit(right, input: "301"))
        let retries = SpeedPracticeFlow.retryQuestions(from: [right, wrong, fresh])
        precondition(retries.count == 1 && retries[0].id == wrong.id)
        precondition(retries[0].expression == wrong.expression && retries[0].answer == wrong.answer)
        precondition(retries[0].input.isEmpty && retries[0].isCorrect == nil && retries[0].timeUsed == 0)
        precondition(SpeedPracticeFlow.retryQuestions(from: [right]).isEmpty)
        precondition(wrong.input == "50" && wrong.isCorrect == false) // History source is untouched.
        precondition(SpeedPracticeFlow.durationText(59.6) == "1:00")
        precondition(SpeedPracticeFlow.durationText(2.2) == "0:02")
        print("PASS manual submit validity, already-submitted guard, original-question retry, all-correct retry, history preservation and elapsed-time formatting")
    }
}
