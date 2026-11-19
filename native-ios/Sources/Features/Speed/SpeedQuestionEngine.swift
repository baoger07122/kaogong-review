import Foundation

struct SpeedQuestionBatchAccumulator {
    let targetCount: Int
    private(set) var questions: [SpeedQuestion] = []
    private(set) var usedExpressions: Set<String> = []

    init(targetCount: Int) {
        self.targetCount = max(1, targetCount)
    }

    var isComplete: Bool { questions.count == targetCount }
    var completedQuestions: [SpeedQuestion]? { isComplete ? questions : nil }

    func contains(expression: String) -> Bool {
        usedExpressions.contains(expression)
    }

    @discardableResult
    mutating func appendIfUnique(_ question: SpeedQuestion) -> Bool {
        guard questions.count < targetCount,
              usedExpressions.insert(question.expression).inserted else { return false }
        questions.append(question)
        return true
    }
}

enum SpeedQuestionEngine {
    static func questions(
        types: [SpeedTypeKey],
        count: Int,
        sequential: Bool,
        estimates: [SpeedEstimateRow],
        customMode: SpeedCustomNumberMode? = nil,
        fixedNumbers: [Int] = [],
        rangeMinimum: Int = 1,
        rangeMaximum: Int = 99
    ) -> [SpeedQuestion] {
        let available = types.filter(\.isAvailable)
        guard !available.isEmpty else { return [] }
        let targetCount = max(1, count)
        var batch = SpeedQuestionBatchAccumulator(targetCount: targetCount)
        var exhaustedTypes = Set<SpeedTypeKey>()

        while !batch.isComplete {
            let preferredType = sequential
                ? available[batch.questions.count % available.count]
                : available.randomElement() ?? available[0]
            let candidates: [SpeedTypeKey]
            if sequential {
                let start = available.firstIndex(of: preferredType) ?? 0
                candidates = Array(available[start...]) + Array(available[..<start])
            } else {
                candidates = [preferredType] + available.filter { $0 != preferredType }.shuffled()
            }

            var nextQuestion: SpeedQuestion?
            for type in candidates where !exhaustedTypes.contains(type) {
                // Rejection sampling is cheap for the broad practice types. If the
                // random stream collides repeatedly, switch to a lazy ordered scan
                // instead of accepting a duplicate or building a full question pool.
                for _ in 0..<8 {
                    guard let candidate = make(type: type, estimates: estimates) else { break }
                    let finalQuestion = applyCustomNumber(
                        to: candidate,
                        mode: customMode,
                        fixedNumbers: fixedNumbers,
                        rangeMinimum: rangeMinimum,
                        rangeMaximum: rangeMaximum
                    )
                    if !batch.contains(expression: finalQuestion.expression) {
                        nextQuestion = finalQuestion
                        break
                    }
                }
                if nextQuestion == nil {
                    nextQuestion = firstUnusedQuestion(
                        type: type,
                        usedExpressions: batch.usedExpressions,
                        estimates: estimates,
                        customMode: customMode,
                        fixedNumbers: fixedNumbers,
                        rangeMinimum: rangeMinimum,
                        rangeMaximum: rangeMaximum
                    )
                    if nextQuestion == nil {
                        exhaustedTypes.insert(type)
                    }
                }
                if nextQuestion != nil { break }
            }

            guard let nextQuestion else { return [] }
            guard batch.appendIfUnique(nextQuestion) else { return [] }
        }
        return batch.completedQuestions ?? []
    }

    /// Finds the first available unique question lazily. The candidate space is
    /// walked only after eight random collisions for a slot, and stops as soon as
    /// one unused final expression is found.
    private static func firstUnusedQuestion(
        type: SpeedTypeKey,
        usedExpressions: Set<String>,
        estimates: [SpeedEstimateRow],
        customMode: SpeedCustomNumberMode?,
        fixedNumbers: [Int],
        rangeMinimum: Int,
        rangeMaximum: Int
    ) -> SpeedQuestion? {
        var found: SpeedQuestion?
        func accept(_ candidate: SpeedQuestion) -> Bool {
            let final = applyCustomNumber(
                to: candidate,
                mode: customMode,
                fixedNumbers: fixedNumbers,
                rangeMinimum: rangeMinimum,
                rangeMaximum: rangeMaximum
            )
            guard !usedExpressions.contains(final.expression) else { return false }
            found = final
            return true
        }

        switch type {
        case .addsub2, .add3, .addsub3:
            let lower = type == .addsub2 ? 10 : 100
            let upper = type == .addsub2 ? 99 : 999
            for a in lower...upper {
                for b in lower...upper {
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(a) + \(b)", answer: Double(a + b))) { return found }
                    if type != .add3,
                       accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(a + b) − \(b)", answer: Double(a))) { return found }
                }
            }
        case .sub3:
            for a in 300...999 {
                for b in 100..<a where accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(a) − \(b)", answer: Double(a - b))) {
                    return found
                }
            }
        case .mul2x1, .mul3x1:
            let lower = type == .mul2x1 ? 10 : 100
            let upper = type == .mul2x1 ? 99 : 999
            for a in lower...upper {
                for b in 2...9 where accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(a) × \(b)", answer: Double(a * b))) {
                    return found
                }
            }
        case .div3x1:
            let allowedDivisors: [Int]
            if customMode == .fixed {
                allowedDivisors = Array(Set(fixedNumbers.filter { (2...19).contains($0) })).sorted()
            } else if customMode == .range {
                allowedDivisors = (2...19).filter { $0 >= rangeMinimum && $0 <= rangeMaximum }
            } else {
                allowedDivisors = []
            }
            for n in 100...999 {
                let divisors = allowedDivisors.isEmpty ? Array(2...9) : allowedDivisors
                for d in divisors {
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(n) ÷ \(d)", answer: rounded(Double(n) / Double(d)))) { return found }
                }
            }
        case .div5x3:
            for n in 10_000...99_999 {
                for d in 100...999 {
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(n) ÷ \(d)", answer: rounded(Double(n) / Double(d)))) { return found }
                }
            }
        case .spDen:
            let pool: [(Double, String)] = [(5, "5%"), (12.5, "12.5%"), (25, "25%"), (37.5, "37.5%"), (50, "50%"), (75, "75%"), (87.5, "87.5%")]
            for n in 40...400 {
                for item in pool {
                    let answer = Double(Int((Double(n) * item.0 / 100).rounded()))
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "\(n) × \(item.1)", answer: answer)) { return found }
                }
            }
        case .est05:
            for source in 101...999 {
                let match = SpeedEstimateRules.approximation(for: source, rows: estimates)
                guard SpeedEstimateRules.isUseful(source: source, approximate: match.value) else { continue }
                for initial in SpeedEstimateRules.resultRange(source: source, approximate: match.value) {
                    let problem = SpeedEstimateProblem(source: source, approximate: match.value, initialResult: initial, isUserDefined: match.userDefined)
                    let answer = (Double(initial) * Double(match.value) / Double(source) * 100).rounded() / 100
                    let candidate = SpeedQuestion(
                        id: UUID().uuidString,
                        type: type,
                        expression: "\(source)→\(match.value)，\(initial)→?",
                        answer: answer,
                        estimate: problem
                    )
                    if accept(candidate) { return found }
                }
            }
        case .base:
            for base in 100...9_999 {
                for rate in 2...30 {
                    let current = Int((Double(base) * Double(100 + rate) / 100).rounded())
                    let answer = Double(Int((Double(current) * 100 / Double(100 + rate)).rounded()))
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "现期 \(current)，同比 +\(rate)%，求基期", answer: answer)) { return found }
                }
            }
        case .growth:
            for base in 100...9_999 {
                for rate in 2...30 {
                    let answer = Double(Int((Double(base * rate) / 100).rounded()))
                    if accept(SpeedQuestion(id: UUID().uuidString, type: type, expression: "基期 \(base)，增长率 \(rate)%，求增量", answer: answer)) { return found }
                }
            }
        case .dataReal:
            return nil
        }
        return found
    }

    static func make(type: SpeedTypeKey, estimates: [SpeedEstimateRow]) -> SpeedQuestion? {
        let expression: String
        let answer: Double
        switch type {
        case .addsub2:
            let a = random(10...99), b = random(10...99)
            if Bool.random() { expression = "\(a) + \(b)"; answer = Double(a + b) }
            else { expression = "\(a + b) − \(b)"; answer = Double(a) }
        case .add3:
            let a = random(100...999), b = random(100...999); expression = "\(a) + \(b)"; answer = Double(a + b)
        case .sub3:
            let a = random(300...999), b = random(100...(a - 1)); expression = "\(a) − \(b)"; answer = Double(a - b)
        case .addsub3:
            let a = random(100...999), b = random(100...999)
            if Bool.random() { expression = "\(a) + \(b)"; answer = Double(a + b) }
            else { expression = "\(a + b) − \(b)"; answer = Double(a) }
        case .mul2x1:
            let a = random(10...99), b = random(2...9); expression = "\(a) × \(b)"; answer = Double(a * b)
        case .mul3x1:
            let a = random(100...999), b = random(2...9); expression = "\(a) × \(b)"; answer = Double(a * b)
        case .div3x1:
            let n = random(100...999), d = random(2...9); expression = "\(n) ÷ \(d)"; answer = rounded(Double(n) / Double(d))
        case .div5x3:
            let n = random(10_000...99_999), d = random(100...999); expression = "\(n) ÷ \(d)"; answer = rounded(Double(n) / Double(d))
        case .spDen:
            let pool: [(Double, String)] = [(5, "5%"), (12.5, "12.5%"), (25, "25%"), (37.5, "37.5%"), (50, "50%"), (75, "75%"), (87.5, "87.5%")]
            let item = pool.randomElement() ?? pool[0], n = random(40...400)
            expression = "\(n) × \(item.1)"; answer = Double(Int((Double(n) * item.0 / 100).rounded()))
        case .est05:
            return SpeedEstimateRules.question(rows: estimates)
        case .base:
            let base = random(100...9999), rate = random(2...30), current = Int((Double(base) * Double(100 + rate) / 100).rounded())
            expression = "现期 \(current)，同比 +\(rate)%，求基期"; answer = Double(Int((Double(current) * 100 / Double(100 + rate)).rounded()))
        case .growth:
            let base = random(100...9999), rate = random(2...30)
            expression = "基期 \(base)，增长率 \(rate)%，求增量"; answer = Double(Int((Double(base * rate) / 100).rounded()))
        case .dataReal:
            return nil
        }
        return SpeedQuestion(id: UUID().uuidString, type: type, expression: expression, answer: answer)
    }

    static func isCorrect(input: String, answer: Double, type _: SpeedTypeKey) -> Bool {
        guard let value = Double(input.replacingOccurrences(of: "，", with: ".")) else { return false }
        return abs(value - answer) <= max(0.011, abs(answer) * 0.03)
    }

    static func errorPercentage(input: String, answer: Double) -> Double? {
        guard let value = Double(input.replacingOccurrences(of: "，", with: ".")) else { return nil }
        let error = abs(value - answer)
        guard abs(answer) >= 0.000_000_001 else { return error < 0.000_000_001 ? 0 : 999 }
        return (error / abs(answer) * 1_000).rounded() / 10
    }

    static func answerText(_ value: Double) -> String {
        value.rounded() == value ? String(Int(value)) : String(format: "%.2f", value)
    }

    static func applyCustomNumber(
        to question: SpeedQuestion,
        mode: SpeedCustomNumberMode?,
        fixedNumbers: [Int],
        rangeMinimum: Int,
        rangeMaximum: Int
    ) -> SpeedQuestion {
        guard let mode, mode != .none else { return question }
        // Standard practice remains one-digit; custom practice intentionally
        // supports divisors through 19 (for example, three-digit / 11).
        if question.type == .div3x1 {
            let valid: [Int]
            switch mode {
            case .fixed: valid = fixedNumbers.filter { (2...19).contains($0) }
            case .range: valid = (2...19).filter { $0 >= rangeMinimum && $0 <= rangeMaximum }
            case .none: return question
            }
            guard let divisor = valid.randomElement(),
                  let numerator = question.expression.components(separatedBy: " ÷ ").first.flatMap(Double.init) else { return question }
            return SpeedQuestion(id: question.id, type: question.type,
                expression: "\(Int(numerator)) ÷ \(divisor)", answer: rounded(numerator / Double(divisor)))
        }
        let replacement: Int
        switch mode {
        case .none:
            return question
        case .fixed:
            let values = fixedNumbers.filter { (1...9).contains($0) }
            guard let value = values.randomElement() else { return question }
            replacement = value
        case .range:
            let lower = min(max(1, rangeMinimum), 999)
            let upper = min(max(lower, rangeMaximum), 999)
            replacement = random(lower...upper)
        }

        let operators = [" + ", " − ", " × ", " ÷ "]
        guard let operation = operators.first(where: { question.expression.contains($0) }) else { return question }
        let parts = question.expression.components(separatedBy: operation)
        guard parts.count == 2, let first = Double(parts[0]), Double(parts[1]) != nil else { return question }

        let answer: Double
        switch operation {
        case " + ": answer = first + Double(replacement)
        case " − ": answer = first - Double(replacement)
        case " × ": answer = first * Double(replacement)
        case " ÷ ": answer = rounded(first / Double(replacement))
        default: return question
        }
        return SpeedQuestion(
            id: question.id,
            type: question.type,
            expression: "\(parts[0])\(operation)\(replacement)",
            answer: rounded(answer)
        )
    }

    private static func random(_ range: ClosedRange<Int>) -> Int { Int.random(in: range) }
    private static func rounded(_ value: Double) -> Double { (value * 100).rounded() / 100 }
}
