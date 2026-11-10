import SwiftUI

struct SpeedAccuracyTrendChart: View {
    let days: [SpeedDailyStatistics]
    let rangeDays: Int

    @State private var selectedIndex: Int?
    @State private var chartWidth: CGFloat = 1

    private var selectedDay: SpeedDailyStatistics? {
        guard let selectedIndex, days.indices.contains(selectedIndex) else { return nil }
        return days[selectedIndex]
    }

    private var defaultSelection: Int? {
        days.indices.reversed().first { days[$0].accuracy != nil || days[$0].secondsPerTenQuestions != nil }
            ?? days.indices.last
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let selectedDay {
                HStack(spacing: 10) {
                    Text(selectedDay.date.formatted(.dateTime.month().day()))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("正确率  \(accuracyText(selectedDay.accuracy))")
                    Text("每10题  \(timeText(selectedDay.secondsPerTenQuestions))")
                }
                .font(.system(size: 10, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                metricHeader("正确率", value: selectedDay.map { accuracyText($0.accuracy) } ?? "—", color: AppTheme.accent)
                plot(values: days.map(\.accuracy), maximum: 1, color: AppTheme.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                let timeValues = days.map(\.secondsPerTenQuestions)
                let maximum = max(1, timeValues.compactMap { $0 }.max() ?? 1)
                metricHeader("每10题平均用时", value: selectedDay.map { timeText($0.secondsPerTenQuestions) } ?? "—", color: AppTheme.warning)
                plot(values: timeValues, maximum: maximum, color: AppTheme.warning)
            }

            HStack(spacing: 0) {
                let step = rangeDays <= 7 ? 1 : max(1, Int(ceil(Double(days.count) / 6)))
                ForEach(days.indices, id: \.self) { index in
                    let shouldLabel = rangeDays <= 7 || index.isMultiple(of: step) || index == days.count - 1
                    Text(shouldLabel ? days[index].date.formatted(.dateTime.month().day()) : "")
                        .font(.system(size: 9))
                        .foregroundStyle(selectedIndex == index ? AppTheme.accent : Color.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: SpeedTrendChartWidthKey.self, value: geometry.size.width)
            }
            .allowsHitTesting(false)
        }
        .onPreferenceChange(SpeedTrendChartWidthKey.self) { chartWidth = max(1, $0) }
        .contentShape(Rectangle())
        .gesture(SpatialTapGesture().onEnded { value in
            guard !days.isEmpty else { return }
            let position = min(max(value.location.x / chartWidth, 0), 1)
            let estimate = Int((position * CGFloat(days.count - 1)).rounded())
            selectedIndex = min(max(estimate, 0), days.count - 1)
        })
        .onAppear { selectedIndex = defaultSelection }
        .onChange(of: days.count) { _, _ in selectedIndex = defaultSelection }
    }

    private func metricHeader(_ title: String, value: String, color: Color) -> some View {
        HStack {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(size: 10, weight: .medium)).monospacedDigit()
        }
    }

    private func plot(values: [Double?], maximum: Double, color: Color) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let lastIndex = max(1, values.count - 1)
            ZStack {
                ForEach(0..<3, id: \.self) { line in
                    Rectangle()
                        .fill(Color.primary.opacity(0.045))
                        .frame(height: 0.5)
                        .offset(y: CGFloat(line) * (height - 1) / 2 - height / 2)
                }
                Path { path in
                    var isDrawingSegment = false
                    for index in values.indices {
                        guard let value = values[index] else {
                            isDrawingSegment = false
                            continue
                        }
                        let x = CGFloat(index) * width / CGFloat(lastIndex)
                        let normalized = min(max(value / max(maximum, 0.0001), 0), 1)
                        let point = CGPoint(x: x, y: height - CGFloat(normalized) * (height - 8) - 4)
                        if isDrawingSegment { path.addLine(to: point) }
                        else { path.move(to: point); isDrawingSegment = true }
                    }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                ForEach(values.indices, id: \.self) { index in
                    if let value = values[index] {
                        let x = CGFloat(index) * width / CGFloat(lastIndex)
                        let normalized = min(max(value / max(maximum, 0.0001), 0), 1)
                        Circle()
                            .fill(Color.white)
                            .overlay(Circle().stroke(color, lineWidth: 1.8))
                            .frame(width: selectedIndex == index ? 8 : 6, height: selectedIndex == index ? 8 : 6)
                            .position(x: x, y: height - CGFloat(normalized) * (height - 8) - 4)
                    }
                }
            }
        }
        .frame(height: 54)
    }

    private func accuracyText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func timeText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return SpeedPracticeFlow.durationText(value)
    }
}

private struct SpeedTrendChartWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 1
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
