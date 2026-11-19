import Foundation

@main
struct SpeedEstimateRulesTests {
    static func main() throws {
        func row(_ a: Int, _ b: Int, _ v: Int) -> SpeedEstimateRow {
            .init(id: "\(a)", minimum: a, maximum: b, value: v)
        }
        let rows = [row(580, 599, 600), row(101, 129, 125)]
        precondition(SpeedEstimateRules.sorted(rows).map(\.minimum) == [101, 580])
        precondition(SpeedEstimateRules.validationError(rows) == nil)
        precondition(SpeedEstimateRules.validationError([row(101, 200, 125), row(200, 300, 250)]) != nil)
        for invalid in [row(100, 110, 100), row(200, 199, 200), row(1000, 1001, 999), row(101, 999, 1000)] {
            precondition(!SpeedEstimateRules.isValid(invalid))
        }
        precondition(SpeedEstimateRules.uncovered(rows) == [130...579, 600...999])
        precondition(SpeedEstimateRules.uncovered([]) == [101...999])
        precondition(SpeedEstimateRules.uncovered([row(101, 999, 500)]).isEmpty)
        for a in 101...129 { precondition(SpeedEstimateRules.approximation(for: a, rows: rows).value == 125) }
        precondition(SpeedEstimateRules.approximation(for: 589, rows: rows).value == 600)
        precondition(SpeedEstimateRules.approximation(for: 589, rows: rows).userDefined)
        precondition(!SpeedEstimateRules.approximation(for: 500, rows: rows).userDefined)
        precondition(!SpeedEstimateRules.isUseful(source: 251, approximate: 250))
        precondition(SpeedEstimateRules.isUseful(source: 589, approximate: 600))
        for _ in 0..<500 {
            let generated = SpeedEstimateRules.question(rows: rows)!
            let problem = generated.estimate!
            precondition(SpeedEstimateRules.correctionRatio(source: problem.source, approximate: problem.approximate) >= 0.015)
        }
        for a in 101...999 {
            for b in [100, 125, 600, 999] {
                let q = SpeedEstimateRules.question(source: a, rows: [row(a, a, b)])
                let p = q.estimate!
                precondition((100...999).contains(p.initialResult))
                precondition(q.answer >= 100 && q.answer <= 999)
                precondition(q.answer == (Double(p.initialResult) * Double(b) / Double(a) * 100).rounded() / 100)
            }
            let q = SpeedEstimateRules.question(source: a, rows: [])
            precondition((100...999).contains(q.estimate!.approximate))
            precondition(!q.estimate!.isUserDefined)
        }
        let modes: [SpeedCustomNumberMode?] = [nil, .fixed, .range]
        for mode in modes {
            for range in [(1, 1), (2, 9), (40, 99), (1, 999)] {
                let batch = SpeedQuestionEngine.questions(types: [.div3x1], count: 100, sequential: false,
                    estimates: [], customMode: mode, fixedNumbers: [1, 2, 9, 11, 19, 40], rangeMinimum: range.0, rangeMaximum: range.1)
                for q in batch {
                    let divisor = Int(q.expression.components(separatedBy: " ÷ ")[1])!
                    precondition((mode == nil ? 2...9 : 2...19).contains(divisor))
                }
            }
        }
        let collisionSourceOne = SpeedQuestion(id: "collision-a", type: .mul3x1, expression: "568 × 2", answer: 1_136)
        let collisionSourceTwo = SpeedQuestion(id: "collision-b", type: .mul3x1, expression: "568 × 9", answer: 5_112)
        let fixedEightOne = SpeedQuestionEngine.applyCustomNumber(
            to: collisionSourceOne, mode: .fixed, fixedNumbers: [8], rangeMinimum: 1, rangeMaximum: 9
        )
        let fixedEightTwo = SpeedQuestionEngine.applyCustomNumber(
            to: collisionSourceTwo, mode: .fixed, fixedNumbers: [8], rangeMinimum: 1, rangeMaximum: 9
        )
        precondition(fixedEightOne.expression == "568 × 8" && fixedEightTwo.expression == fixedEightOne.expression,
                     "different source multipliers must collide after applying the same custom fixed multiplier")
        precondition(fixedEightOne.answer == 4_544 && fixedEightTwo.answer == fixedEightOne.answer,
                     "custom multiplication collision must recalculate the final answer")
        var customBatch = SpeedQuestionBatchAccumulator(targetCount: 3)
        precondition(customBatch.appendIfUnique(fixedEightOne), "first custom expression should enter the group")
        precondition(!customBatch.appendIfUnique(fixedEightTwo), "duplicate final custom expression should be rejected despite a distinct id")
        let sameAnswerOne = SpeedQuestion(id: "same-answer-a", type: .mul3x1, expression: "190 × 4", answer: 760)
        let sameAnswerTwo = SpeedQuestion(id: "same-answer-b", type: .mul3x1, expression: "380 × 2", answer: 760)
        precondition(customBatch.appendIfUnique(sameAnswerOne) && customBatch.appendIfUnique(sameAnswerTwo),
                     "distinct expressions with the same answer must both remain eligible")
        precondition(customBatch.isComplete && customBatch.completedQuestions?.count == 3,
                     "the group should complete when it reaches its unique expression target")

        var crossTypeBatch = SpeedQuestionBatchAccumulator(targetCount: 2)
        let sameExpressionAdd = SpeedQuestion(id: "add-a", type: .add3, expression: "100 + 100", answer: 200)
        let sameExpressionMixed = SpeedQuestion(id: "add-b", type: .addsub3, expression: "100 + 100", answer: 200)
        precondition(crossTypeBatch.appendIfUnique(sameExpressionAdd), "first expression should enter a mixed-type group")
        precondition(!crossTypeBatch.appendIfUnique(sameExpressionMixed), "an expression already used by another type must be rejected")

        var insufficientBatch = SpeedQuestionBatchAccumulator(targetCount: 2)
        precondition(insufficientBatch.appendIfUnique(sameAnswerOne), "a unique candidate should be retained while filling")
        precondition(!insufficientBatch.appendIfUnique(sameAnswerOne), "repeated candidate must not inflate the completed count")
        precondition(!insufficientBatch.isComplete && insufficientBatch.completedQuestions == nil,
                     "an undersized batch must not be exposed as a complete practice round")
        let legacy = SpeedQuestion(id: "old", type: .add3, expression: "100 + 200", answer: 300)
        let encoded = try JSONEncoder().encode(legacy)
        precondition(!String(decoding: encoded, as: UTF8.self).contains("estimate"))
        let legacyRestored = try JSONDecoder().decode(SpeedQuestion.self, from: encoded)
        precondition(legacyRestored == legacy)
        let estimate = SpeedEstimateRules.question(source: 589, rows: rows)
        let restored = try JSONDecoder().decode(SpeedQuestion.self, from: JSONEncoder().encode(estimate))
        precondition(restored == estimate)
        precondition(SpeedTypeKey.sub3.ratingThresholds == .init(excellent: 24, good: 30, pass: 38))
        print("PASS estimate rules, divisor cases, unique group expressions, custom collisions, shortage handling, and old/new history coding")
    }
}
