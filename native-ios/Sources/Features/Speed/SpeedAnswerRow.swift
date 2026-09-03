import SwiftUI
import UIKit

/// The answer grows with its text; center the entire equation, not a fixed answer slot.
struct SpeedAnswerRow: View {
    let expression: String
    let input: String
    let questionID: String
    let inputRevision: Int
    var nightMode = false

    var body: some View {
        GeometryReader { geometry in
            let available = max(1, geometry.size.width - 24)
            let baseFont = UIFont.systemFont(ofSize: 42, weight: .regular)
            let expressionWidth = (expression as NSString).size(withAttributes: [.font: baseFont, .kern: 1]).width
            let equalsWidth = ("=" as NSString).size(withAttributes: [.font: baseFont, .kern: 1]).width
            // Narrow-window fallback depends only on the question, never the entered digits.
            let scale = min(1, max(0.1, (available - 56) / (expressionWidth + equalsWidth)))
            let fontSize = 42 * scale
            let fixedWidth = (expressionWidth + equalsWidth) * scale
            let textWidth = (input as NSString).size(withAttributes: [.font: UIFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)]).width + 4
            let answerWidth = min(max(40, textWidth), min(geometry.size.width * 0.64, available - fixedWidth - 16))

            HStack(spacing: 8) {
                SpeedAnimatedText(text: expression, fontSize: fontSize, nightMode: nightMode,
                                  motion: .expression(questionID), kerning: scale)
                    .frame(width: expressionWidth * scale, height: 56)
                Text("=").kerning(scale)
                    .frame(width: equalsWidth * scale)
                SpeedAnimatedText(text: input, fontSize: fontSize, nightMode: nightMode,
                                  motion: .answer(inputRevision))
                .frame(width: answerWidth, height: 56)
            }
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(nightMode ? Color(white: 245 / 255.0) : Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Layout stays stable; the two native text surfaces animate independently.
            .transaction { $0.animation = nil; $0.disablesAnimations = true }
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("speed-answer")
        .accessibilityValue(input)
        .accessibilityLabel("\(expression) 等于 \(input.isEmpty ? "空" : input)")
    }
}
