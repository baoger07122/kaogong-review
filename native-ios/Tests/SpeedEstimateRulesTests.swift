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
                    estimates: [], customMode: mode, fixedNumbers: [1, 2, 9, 40], rangeMinimum: range.0, rangeMaximum: range.1)
                for q in batch {
                    let divisor = Int(q.expression.components(separatedBy: " ÷ ")[1])!
                    precondition((2...9).contains(divisor))
                }
            }
        }
        let legacy = SpeedQuestion(id: "old", type: .add3, expression: "100 + 200", answer: 300)
        let encoded = try JSONEncoder().encode(legacy)
        precondition(!String(decoding: encoded, as: UTF8.self).contains("estimate"))
        let legacyRestored = try JSONDecoder().decode(SpeedQuestion.self, from: encoded)
        precondition(legacyRestored == legacy)
        let estimate = SpeedEstimateRules.question(source: 589, rows: rows)
        let restored = try JSONDecoder().decode(SpeedQuestion.self, from: JSONEncoder().encode(estimate))
        precondition(restored == estimate)
        print("PASS all 899 sources, 4 scale extremes, interval boundaries/coverage/sorting/overlap, fallback, 1200 divisor cases, old/new history coding")
    }
}
