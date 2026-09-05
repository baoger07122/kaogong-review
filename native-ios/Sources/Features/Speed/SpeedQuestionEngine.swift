import Foundation

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
        return (0..<max(1, count)).compactMap { index in
            let type = sequential ? available[index % available.count] : available.randomElement() ?? available[0]
            guard let question = make(type: type, estimates: estimates) else { return nil }
            return applyCustomNumber(
                to: question,
                mode: customMode,
                fixedNumbers: fixedNumbers,
                rangeMinimum: rangeMinimum,
                rangeMaximum: rangeMaximum
            )
        }
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

    private static func applyCustomNumber(
        to question: SpeedQuestion,
        mode: SpeedCustomNumberMode?,
        fixedNumbers: [Int],
        rangeMinimum: Int,
        rangeMaximum: Int
    ) -> SpeedQuestion {
        guard let mode, mode != .none else { return question }
        // A three-digit / one-digit exercise must remain that type in every custom mode.
        if question.type == .div3x1 {
            let valid: [Int]
            switch mode {
            case .fixed: valid = fixedNumbers.filter { (2...9).contains($0) }
            case .range: valid = (2...9).filter { $0 >= rangeMinimum && $0 <= rangeMaximum }
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
