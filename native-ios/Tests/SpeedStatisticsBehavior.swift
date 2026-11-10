import Foundation

@main
struct SpeedStatisticsBehavior {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dayOne = date(2026, 11, 3, calendar: calendar)
        let dayFour = date(2026, 11, 7, calendar: calendar)
        let now = date(2026, 11, 10, calendar: calendar)
        let records = [
            record("a1", dayOne, "两位数加减", totalTime: 100, correct: 8, count: 10),
            record("a2", dayOne, "两位数加减", totalTime: 200, correct: 0, count: 5),
            record("wrong", dayFour, "三位数加法", totalTime: 80, correct: 0, count: 10),
            record("custom1", dayOne, "自定义练习 两位数加减", totalTime: 60, correct: 5, count: 5),
            record("custom2", dayOne, "自定义练习 三位数乘一位数", totalTime: 100, correct: 4, count: 5)
        ]

        let selected = SpeedStatisticsSnapshot(records: records, selectedType: "两位数加减", dayCount: 7, now: now, calendar: calendar)
        expect(selected.selectedAggregate?.practiceCount == 2, "top metrics count sessions for the chosen type")
        expect(abs((selected.selectedAggregate?.accuracy ?? 0) - 8.0 / 15.0) < 0.0001, "accuracy is total correct divided by total questions")
        expect(abs((selected.selectedAggregate?.averageTime ?? 0) - 200) < 0.0001, "average time is total seconds per ten questions")
        expect(selected.trend.count == 7 && selected.trend.first?.accuracy == nil, "the seven day trend keeps empty dates as gaps")
        expect(selected.trend.last?.accuracy == nil, "other types do not affect the selected trend")
        expect(selected.crossTypeAggregates.first(where: { $0.name == "自定义练习" })?.practiceCount == 2,
            "mixed custom sessions stay grouped as their own cross-type aggregate")

        let all = SpeedStatisticsSnapshot(records: records, selectedType: "全部", dayCount: 30, now: now, calendar: calendar)
        expect(all.trend.count == 30, "the 30 day range contains every local date")
        let allWrong = all.trend.first { calendar.isDate($0.date, inSameDayAs: dayFour) }
        expect(allWrong?.accuracy == 0, "a date with questions that were all wrong is a real zero")
        expect(allWrong?.secondsPerTenQuestions == 80, "per-ten time uses total duration over total questions")
        expect(all.trend.first?.accuracy == nil && all.trend.first?.secondsPerTenQuestions == nil,
            "a date with no records remains missing")
        expect(all.typeOptions.contains("自定义练习"), "custom sessions have one selectable filter")
        expect(all.typeOptions.filter { $0 == "自定义练习" }.count == 1, "custom sessions are not split into constituent practice types")
    }

    private static func record(_ id: String, _ date: Date, _ name: String, totalTime: Double, correct: Int, count: Int) -> SpeedRecord {
        SpeedRecord(id: id, date: date, name: name, mode: .train, totalTime: totalTime, correctCount: correct, totalCount: count, details: [])
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, calendar: Calendar) -> Date {
        calendar.startOfDay(for: calendar.date(from: DateComponents(year: year, month: month, day: day))!)
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
