import SwiftUI

struct SpeedAccuracyTrendChart: View {
    let days: [SpeedDailyAccuracy]

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let count = max(days.count, 2)
                let points = days.enumerated().map { index, day in
                    CGPoint(
                        x: CGFloat(index) * width / CGFloat(count - 1),
                        y: height - CGFloat(min(max(day.accuracy, 0), 1)) * (height - 16) - 8
                    )
                }
                ZStack {
                    ForEach(0..<4, id: \.self) { line in
                        Rectangle().fill(Color.primary.opacity(0.045)).frame(height: 0.5)
                            .offset(y: CGFloat(line) * (height - 1) / 3 - height / 2)
                    }
                    Path { path in
                        guard let first = points.first else { return }
                        path.move(to: first)
                        for point in points.dropFirst() { path.addLine(to: point) }
                    }
                    .stroke(AppTheme.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                        Circle().fill(Color.white).overlay(Circle().stroke(AppTheme.accent, lineWidth: 2))
                            .frame(width: 8, height: 8)
                            .position(point)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(days) { day in
                    VStack(spacing: 1) {
                        Text("\(Int((day.accuracy * 100).rounded()))%")
                        Text(day.date.formatted(.dateTime.month().day()))
                    }
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
