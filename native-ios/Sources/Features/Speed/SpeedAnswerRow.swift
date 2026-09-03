import SwiftUI
import UIKit

/// The answer grows with its text; center the entire equation, not a fixed answer slot.
struct SpeedAnswerRow: View {
    let expression: String
    let input: String
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
                Text(expression).kerning(scale)
                    .frame(width: expressionWidth * scale)
                Text("=").kerning(scale)
                    .frame(width: equalsWidth * scale)
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        HStack(spacing: 0) {
                            Text(input)
                                .font(.system(size: fontSize, weight: .regular, design: .monospaced))
                                .fixedSize()
                            Color.clear.frame(width: 0, height: 1).id("answer-end")
                        }
                        .frame(minWidth: max(0, answerWidth - 4), minHeight: 56)
                        .padding(.horizontal, 2)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: input) { _, _ in proxy.scrollTo("answer-end", anchor: .trailing) }
                }
                .frame(width: answerWidth, height: 56)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(nightMode ? Color.white.opacity(0.4) : Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0).opacity(0.32)).frame(height: 2.5)
                }
                .modifier(SpeedInputPulse(trigger: inputRevision))
            }
            .font(.system(size: fontSize, weight: .regular))
            .foregroundStyle(nightMode ? Color(white: 245 / 255.0) : Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0))
            .lineLimit(1)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 56)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(expression) 等于 \(input.isEmpty ? "空" : input)")
    }
}
