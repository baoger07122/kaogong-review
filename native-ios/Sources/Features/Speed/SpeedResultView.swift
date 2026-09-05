import SwiftUI

struct SpeedResultView: View {
    let questions: [SpeedQuestion]
    let title: String
    let totalTime: Double
    let standard: String
    let onRestart: () -> Void
    let onRetry: () -> Void
    let onReturn: () -> Void
    var showsStandard = true
    var showsFooter = true

    private let ink = Color(red: 31 / 255.0, green: 41 / 255.0, blue: 55 / 255.0)
    private let headerInk = Color(red: 55 / 255.0, green: 65 / 255.0, blue: 81 / 255.0)
    private let secondaryInk = Color(red: 107 / 255.0, green: 114 / 255.0, blue: 128 / 255.0)
    private let tertiaryInk = Color(red: 156 / 255.0, green: 163 / 255.0, blue: 175 / 255.0)
    private let blue = Color(red: 59 / 255.0, green: 130 / 255.0, blue: 246 / 255.0)
    private let linkBlue = Color(red: 37 / 255.0, green: 99 / 255.0, blue: 235 / 255.0)
    private let red = Color(red: 239 / 255.0, green: 68 / 255.0, blue: 68 / 255.0)
    private let green = Color(red: 16 / 255.0, green: 185 / 255.0, blue: 129 / 255.0)

    var body: some View {
        GeometryReader { geometry in
            let tableWidth = max(420, geometry.size.width - 32)
            ScrollView {
                VStack(spacing: 0) {
                    if showsStandard {
                        Text(standard).font(.system(size: 12)).foregroundStyle(secondaryInk)
                            .frame(height: 18)
                            .padding(.top, 8)
                    }
                    VStack(spacing: 4) {
                        Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                            .frame(height: 30)
                        Text("本次练习用时:\(SpeedPracticeFlow.durationText(totalTime)) 加油")
                            .font(.system(size: 13)).foregroundStyle(secondaryInk)
                            .frame(height: 20)
                    }
                    .padding(.top, 16).padding(.bottom, 12)
                    ScrollView(.horizontal) {
                        VStack(spacing: 0) {
                            tableHeader(width: tableWidth)
                            ForEach(Array(questions.enumerated()), id: \.element.id) { offset, question in
                                tableRow(question, number: offset + 1, width: tableWidth)
                            }
                        }
                        .frame(width: tableWidth)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                        .padding(.horizontal, 16).padding(.bottom, 8)
                    }
                    .scrollIndicators(.hidden)
                }
                .padding(.bottom, 16)
            }
        }
        .background(Color.white)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsFooter {
                HStack(spacing: 10) {
                    footerButton("重来", color: Color(red: 243 / 255.0, green: 244 / 255.0, blue: 246 / 255.0), ink: headerInk, action: onRestart)
                    footerButton("复练", color: Color(red: 239 / 255.0, green: 246 / 255.0, blue: 255 / 255.0), ink: linkBlue, action: onRetry)
                    footerButton("返回", color: blue, ink: .white, bold: true, action: onReturn)
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
                .background(Color.white)
                .overlay(alignment: .top) { Color.black.opacity(0.045).frame(height: 0.5) }
            }
        }
    }

    private func tableHeader(width: CGFloat) -> some View {
        let widths: [CGFloat] = [40, width - 316, 76, 84, 60, 56]
        let titles = ["#", "题目", "正确答案", "你的答案", "误差", "用时"]
        return HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index]).font(.system(size: 12, weight: .bold))
                    .frame(width: widths[index])
            }
        }
        .foregroundStyle(headerInk).frame(height: 38)
        .background(Color(red: 249 / 255.0, green: 250 / 255.0, blue: 251 / 255.0))
    }

    private func tableRow(_ question: SpeedQuestion, number: Int, width: CGFloat) -> some View {
        let correct = question.isCorrect == true
        let error = SpeedQuestionEngine.errorPercentage(input: question.input, answer: question.answer)
        return HStack(spacing: 0) {
            cell("\(number)", width: 40, size: 13, color: tertiaryInk)
            cell(question.expression, width: width - 316, size: 15, weight: .medium)
            cell("= \(SpeedQuestionEngine.answerText(question.answer))", width: 76, size: 15)
            cell(question.input + (correct ? "✓" : "✗"), width: 84, size: 15, weight: .bold, color: correct ? blue : red)
            cell(error.map { String(format: "%.1f%%", $0) } ?? "—", width: 60, size: 13, weight: .semibold, color: correct ? green : red)
            cell(String(format: "%.1fs", question.timeUsed), width: 56, size: 13, color: secondaryInk)
        }
        .frame(height: 47)
        .overlay(alignment: .bottom) { Color.black.opacity(0.045).frame(height: 0.5) }
    }

    private func cell(_ text: String, width: CGFloat, size: CGFloat, weight: Font.Weight = .regular, color: Color? = nil) -> some View {
        Text(text).font(.system(size: size, weight: weight))
            .foregroundStyle(color ?? ink)
            .multilineTextAlignment(.center).frame(width: width)
    }

    private func footerButton(_ title: String, color: Color, ink: Color, bold: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(.system(size: 15, weight: bold ? .bold : .medium))
                .foregroundStyle(ink).frame(maxWidth: .infinity).frame(height: 49)
                .background(color, in: RoundedRectangle(cornerRadius: 14)).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
