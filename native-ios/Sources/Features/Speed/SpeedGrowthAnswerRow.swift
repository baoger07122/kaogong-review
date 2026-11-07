import SwiftUI

struct SpeedGrowthAnswerRow: View {
    let expression: String
    let input: String
    var nightMode = false

    private var presentation: SpeedGrowthPresentation { SpeedGrowthPresentation.parse(expression) }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 13) {
                if presentation.isStructured,
                   let baseValue = presentation.baseValue,
                   let growthRate = presentation.growthRate {
                    HStack(spacing: 10) {
                        valueColumn(label: "基期", value: baseValue)
                        valueColumn(label: "增长率", value: "\(growthRate)%")
                    }
                    .frame(height: 86)
                } else {
                    Text(presentation.fallbackExpression)
                        .font(.system(size: 21, weight: .regular))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 86)
                        .accessibilityLabel(presentation.fallbackExpression)
                }

                Text("求增量")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(nightMode ? Color.white.opacity(0.88) : Color.secondary)

                VStack(spacing: 5) {
                    Text(input.isEmpty ? " " : input)
                        .font(.system(size: 34, weight: .regular, design: .rounded).monospacedDigit())
                        .foregroundStyle(nightMode ? Color(white: 245 / 255.0) : Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0))
                        .lineLimit(1)
                        .minimumScaleFactor(0.45)
                        .frame(maxWidth: .infinity)
                        .frame(height: 43)
                        .accessibilityIdentifier("speed-growth-answer")
                        .accessibilityValue(input)
                    Rectangle()
                        .fill(nightMode ? Color.white.opacity(0.58) : Color.primary.opacity(0.28))
                        .frame(height: 1.5)
                }
                .frame(width: min(280, max(1, geometry.size.width - 40)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 192)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("speed-growth-question")
    }

    private func valueColumn(label: String, value: String) -> some View {
        VStack(spacing: 8) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(nightMode ? Color.white.opacity(0.72) : Color.secondary)
            Text(value)
                .font(.system(size: 30, weight: .medium, design: .rounded).monospacedDigit())
                .foregroundStyle(nightMode ? Color(white: 245 / 255.0) : Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0))
                .lineLimit(1)
                .minimumScaleFactor(0.55)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity)
    }
}
