import Foundation

struct SpeedEstimateProblem: Codable, Equatable {
    let source: Int
    let approximate: Int
    let initialResult: Int
    let isUserDefined: Bool
}

enum SpeedEstimateRules {
    static let minimumCorrectionRatio = 0.015

    static func isValid(_ row: SpeedEstimateRow) -> Bool {
        (101...999).contains(row.minimum) && (row.minimum...999).contains(row.maximum)
            && (100...999).contains(row.value)
    }

    static func sorted(_ rows: [SpeedEstimateRow]) -> [SpeedEstimateRow] {
        rows.sorted { $0.minimum == $1.minimum ? $0.maximum < $1.maximum : $0.minimum < $1.minimum }
    }

    static func validationError(_ rows: [SpeedEstimateRow]) -> String? {
        guard rows.allSatisfy(isValid) else { return "区间须在 101–999 内，起点不能大于终点；估算值须为 100–999。" }
        let ordered = sorted(rows)
        for (left, right) in zip(ordered, ordered.dropFirst()) where left.maximum >= right.minimum {
            return "区间 \(left.minimum)–\(left.maximum) 与 \(right.minimum)–\(right.maximum) 重叠，请先调整。"
        }
        return nil
    }

    static func uncovered(_ rows: [SpeedEstimateRow]) -> [ClosedRange<Int>] {
        var cursor = 101
        var gaps: [ClosedRange<Int>] = []
        for row in sorted(rows.filter(isValid)) {
            if row.minimum > cursor { gaps.append(cursor...(row.minimum - 1)) }
            cursor = max(cursor, row.maximum + 1)
        }
        if cursor <= 999 { gaps.append(cursor...999) }
        return gaps
    }

    /// Deterministic fallback: closest multiple of ten or 125; manual ranges always win.
    static func approximation(for source: Int, rows: [SpeedEstimateRow]) -> (value: Int, userDefined: Bool) {
        if let row = sorted(rows).first(where: { isValid($0) && ($0.minimum...$0.maximum).contains(source) }) {
            return (row.value, true)
        }
        let candidates = Set(Array(stride(from: 100, through: 990, by: 10)) + Array(stride(from: 125, through: 875, by: 125)))
        let closest = candidates.min {
            abs($0 - source) == abs($1 - source) ? $0 < $1 : abs($0 - source) < abs($1 - source)
        } ?? 100
        return (closest, false)
    }

    static func resultRange(source: Int, approximate: Int) -> ClosedRange<Int> {
        let lower = max(100, Int(ceil(100 * Double(source) / Double(approximate))))
        let upper = min(999, Int(floor(999 * Double(source) / Double(approximate))))
        return lower...max(lower, upper)
    }

    static func correctionRatio(source: Int, approximate: Int) -> Double {
        guard source != 0 else { return 0 }
        return abs(Double(source - approximate)) / Double(source)
    }

    static func isUseful(source: Int, approximate: Int) -> Bool {
        correctionRatio(source: source, approximate: approximate) >= minimumCorrectionRatio
    }

    /// Select only questions where rounding changes the source by at least 1.5%.
    /// If a fully user-defined table leaves no useful source, return nil instead of
    /// silently weakening the training threshold.
    static func question(rows: [SpeedEstimateRow]) -> SpeedQuestion? {
        let candidates = (101...999).filter { source in
            let match = approximation(for: source, rows: rows)
            return isUseful(source: source, approximate: match.value)
        }
        guard let source = candidates.randomElement() else { return nil }
        return question(source: source, rows: rows)
    }

    static func question(source: Int, rows: [SpeedEstimateRow]) -> SpeedQuestion {
        let match = approximation(for: source, rows: rows)
        let initial = Int.random(in: resultRange(source: source, approximate: match.value))
        let problem = SpeedEstimateProblem(source: source, approximate: match.value, initialResult: initial, isUserDefined: match.userDefined)
        let answer = (Double(initial) * Double(match.value) / Double(source) * 100).rounded() / 100
        return SpeedQuestion(id: UUID().uuidString, type: .est05,
            expression: "\(source)→\(match.value)，\(initial)→?", answer: answer, estimate: problem)
    }
}
