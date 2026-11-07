import Foundation

struct SpeedGrowthPresentation: Equatable {
    let baseValue: String?
    let growthRate: String?
    let fallbackExpression: String

    var isStructured: Bool { baseValue != nil && growthRate != nil }

    static func parse(_ expression: String) -> SpeedGrowthPresentation {
        let pattern = #"基期[：:]?\s*([0-9０-９]+(?:[,，][0-9０-９]{3})*(?:[.．][0-9０-９]+)?)\s*[，,、;；\s]*增长率\s*([0-9０-９]+(?:[.．][0-9０-９]+)?)\s*[%％]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: expression, range: NSRange(expression.startIndex..., in: expression)),
              let baseRange = Range(match.range(at: 1), in: expression),
              let rateRange = Range(match.range(at: 2), in: expression) else {
            return SpeedGrowthPresentation(baseValue: nil, growthRate: nil, fallbackExpression: expression)
        }

        return SpeedGrowthPresentation(
            baseValue: normalizeDigits(String(expression[baseRange])),
            growthRate: normalizeDigits(String(expression[rateRange])),
            fallbackExpression: expression
        )
    }

    private static func normalizeDigits(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.map { scalar in
            if (0xFF10...0xFF19).contains(scalar.value), let ascii = UnicodeScalar(scalar.value - 0xFF10 + 0x30) {
                return ascii
            }
            if scalar.value == 0xFF0E { return "." }
            if scalar.value == 0xFF0C { return "," }
            return scalar
        }))
    }
}
