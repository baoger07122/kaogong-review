import SwiftUI

/// Layout tokens are from 92-speed-preserved.css (.sc-estp-*).
struct SpeedEstimateExercise: View {
    let problem: SpeedEstimateProblem
    let input: String
    let showInput: Bool
    var nightMode = false

    private let blue = Color(red: 33 / 255.0, green: 98 / 255.0, blue: 216 / 255.0)
    var body: some View {
        GeometryReader { geometry in
            let scale = min(1, max(0.55, (geometry.size.width - 32) / 436))
            VStack(spacing: 0) {
                Text("按 A→B 的比例，把 C 缩放成 D")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .padding(.bottom, 20 * scale)
                row(left: problem.source, scale: scale) {
                    Text("\(problem.approximate)").font(.system(size: 34 * scale, weight: .bold))
                }
                .padding(.bottom, 16 * scale)
                row(left: problem.initialResult, scale: scale) {
                    Text(showInput ? (input.isEmpty ? "答案" : input) : "···")
                        .font(.system(size: 32 * scale, weight: .semibold))
                        .foregroundStyle(input.isEmpty ? Color(red: 184 / 255.0, green: 184 / 255.0, blue: 192 / 255.0) : (nightMode ? .white : Color(red: 29 / 255.0, green: 29 / 255.0, blue: 31 / 255.0)))
                        .lineLimit(1).minimumScaleFactor(0.45)
                        .frame(width: 160 * scale, height: 52 * scale)
                        .overlay { RoundedRectangle(cornerRadius: 12 * scale).stroke(Color(red: 142 / 255.0, green: 175 / 255.0, blue: 1), lineWidth: 1.5) }
                        .accessibilityIdentifier("speed-estimate-answer")
                        .accessibilityLabel("修正结果").accessibilityValue(input)
                }
                Text(problem.isUserDefined ? "估算值来源：你的估算表" : "系统估算：取邻近整十数或 125 的倍数；可在估算表覆盖")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.top, 16)
                    .padding(.horizontal, 16)
            }
            .foregroundStyle(nightMode ? .white : Color(red: 29 / 255.0, green: 29 / 255.0, blue: 31 / 255.0))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 220)
        .accessibilityIdentifier("speed-estimate-exercise")
        .accessibilityLabel("估算练习题")
        .accessibilityValue(input)
    }

    private func row<Content: View>(left: Int, scale: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Text("\(left)").font(.system(size: 34 * scale, weight: .bold))
                .padding(.trailing, 8 * scale)
                .frame(width: 190 * scale, alignment: .trailing)
            Text("→").font(.system(size: 28 * scale)).foregroundStyle(blue).frame(width: 56 * scale)
            content().padding(.leading, 8 * scale).frame(width: 190 * scale, alignment: .leading)
        }
    }
}
