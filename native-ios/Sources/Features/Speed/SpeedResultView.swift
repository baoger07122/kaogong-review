import SwiftUI

struct SpeedResultView: View {
    let questions: [SpeedQuestion]
    let title: String
    let totalTime: Double
    let standard: String
    let onRestart: () -> Void
    let onRetry: () -> Void
    let onReturn: () -> Void
    var growthOnly: Bool? = nil
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

    private var isGrowthOnly: Bool {
        growthOnly ?? (!questions.isEmpty && questions.allSatisfy { $0.type == .growth })
    }

    private var growthColumnWidths: [CGFloat] {
        let baseLength = questions.compactMap { SpeedGrowthPresentation.parse($0.expression).baseValue?.count }.max() ?? 1
        let rateLength = questions.compactMap { SpeedGrowthPresentation.parse($0.expression).growthRate?.count }.max() ?? 1
        let answerLength = questions.map { SpeedQuestionEngine.answerText($0.answer).count }.max() ?? 1
        let inputLength = questions.map { $0.input.count }.max() ?? 0
        return [
            52,
            max(82, CGFloat(baseLength) * 9 + 16),
            max(82, CGFloat(rateLength + 1) * 9 + 16),
            max(96, CGFloat(answerLength) * 9 + 16),
            max(112, CGFloat(inputLength) * 9 + 32),
            82,
            80
        ]
    }

    private var growthTableWidth: CGFloat { growthColumnWidths.reduce(0, +) }

    var body: some View {
        GeometryReader { geometry in
            let tableWidth = max(420, geometry.size.width - 32)
            ScrollView {
                VStack(spacing: 0) {
                    if showsStandard && !isGrowthOnly {
                        Text(standard).font(.system(size: 12)).foregroundStyle(secondaryInk)
                            .frame(height: 18)
                            .padding(.top, 8)
                    }

                    if isGrowthOnly {
                        VStack(spacing: 4) {
                            Text("答对 \(questions.filter { $0.isCorrect == true }.count) / \(questions.count)")
                                .font(.system(size: 19, weight: .bold)).foregroundStyle(ink)
                                .frame(height: 28)
                            Text("用时 \(SpeedPracticeFlow.durationText(totalTime))")
                                .font(.system(size: 13)).foregroundStyle(secondaryInk)
                                .frame(height: 20)
                        }
                        .padding(.top, 16).padding(.bottom, 12)
                    } else {
                        VStack(spacing: 4) {
                            Text(title).font(.system(size: 20, weight: .bold)).foregroundStyle(ink)
                                .frame(height: 30)
                            Text("本次练习用时:\(SpeedPracticeFlow.durationText(totalTime)) 加油")
                                .font(.system(size: 13)).foregroundStyle(secondaryInk)
                                .frame(height: 20)
                        }
                        .padding(.top, 16).padding(.bottom, 12)
                    }

                    if isGrowthOnly {
                        ScrollView(.horizontal) {
                            VStack(spacing: 0) {
                                growthTableHeader(widths: growthColumnWidths)
                                ForEach(Array(questions.enumerated()), id: \.element.id) { offset, question in
                                    growthTableRow(question, number: offset + 1, widths: growthColumnWidths)
                                }
                            }
                            .frame(width: growthTableWidth)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .shadow(color: .black.opacity(0.035), radius: 3, y: 1)
                            .padding(.horizontal, 16).padding(.bottom, 8)
                        }
                        .scrollIndicators(.hidden)
                    } else {
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

    private func growthTableHeader(widths: [CGFloat]) -> some View {
        let titles = ["序号", "基期", "增长率", "参考答案", "你的答案", "误差", "用时"]
        return HStack(spacing: 0) {
            ForEach(titles.indices, id: \.self) { index in
                Text(titles[index])
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(headerInk)
                    .padding(.horizontal, 8)
                    .frame(width: widths[index], alignment: .trailing)
            }
        }
        .frame(height: 38)
        .background(Color(red: 249 / 255.0, green: 250 / 255.0, blue: 251 / 255.0))
    }

    private func growthTableRow(_ question: SpeedQuestion, number: Int, widths: [CGFloat]) -> some View {
        let correct = question.isCorrect == true
        let error = SpeedQuestionEngine.errorPercentage(input: question.input, answer: question.answer)
        let presentation = SpeedGrowthPresentation.parse(question.expression)

        return HStack(spacing: 0) {
            growthCell("\(number)", width: widths[0], color: tertiaryInk)
            if presentation.isStructured,
               let baseValue = presentation.baseValue,
               let growthRate = presentation.growthRate {
                growthCell(baseValue, width: widths[1])
                growthCell("\(growthRate)%", width: widths[2])
            } else {
                Text(presentation.fallbackExpression)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 8)
                    .frame(width: widths[1] + widths[2], alignment: .leading)
            }
            growthCell(SpeedQuestionEngine.answerText(question.answer), width: widths[3])
            growthAnswerCell(question.input, correct: correct, width: widths[4])
            growthCell(error.map { String(format: "%.1f%%", $0) } ?? "—", width: widths[5], size: 13, weight: .semibold, color: correct ? green : red)
            growthCell(String(format: "%.1f秒", question.timeUsed), width: widths[6], size: 13, color: secondaryInk)
        }
        .frame(minHeight: 47)
        .overlay(alignment: .bottom) { Color.black.opacity(0.045).frame(height: 0.5) }
    }

    private func growthCell(
        _ text: String,
        width: CGFloat,
        size: CGFloat = 14,
        weight: Font.Weight = .regular,
        color: Color? = nil,
        alignment: Alignment = .trailing
    ) -> some View {
        Text(text)
            .font(.system(size: size, weight: weight).monospacedDigit())
            .foregroundStyle(color ?? ink)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 8)
            .frame(width: width, alignment: alignment)
    }

    private func growthAnswerCell(_ input: String, correct: Bool, width: CGFloat) -> some View {
        HStack(spacing: 7) {
            Text(input.isEmpty ? "—" : input)
                .foregroundStyle(correct ? blue : red)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(correct ? "✓" : "✗")
                .foregroundStyle(correct ? blue : red)
                .fontWeight(.bold)
        }
        .font(.system(size: 14).monospacedDigit())
        .padding(.horizontal, 8)
        .frame(width: width, alignment: .trailing)
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
