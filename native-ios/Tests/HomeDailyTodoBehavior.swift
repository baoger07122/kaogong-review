import Foundation

@main
struct HomeDailyTodoBehavior {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let dayOne = date(2026, 11, 10, 0, 0, calendar: calendar)
        let dayTwo = date(2026, 11, 11, 0, 0, calendar: calendar)
        let start = date(2026, 11, 10, 20, 15, calendar: calendar)

        expect(HomeDailyTodoPolicy.instanceID(ruleID: "rule-1", on: start, calendar: calendar)
            == HomeDailyTodoPolicy.instanceID(ruleID: "rule-1", on: date(2026, 11, 10, 23, 0, calendar: calendar), calendar: calendar),
            "a recurring rule has one stable instance ID per local day")
        expect(HomeDailyTodoPolicy.instanceID(ruleID: "rule-1", on: dayOne, calendar: calendar)
            != HomeDailyTodoPolicy.instanceID(ruleID: "rule-1", on: dayTwo, calendar: calendar),
            "the next local day receives an independent instance")
        expect(!HomeDailyTodoPolicy.shouldGenerateInstance(startDate: dayTwo, isPaused: false, on: dayOne, calendar: calendar),
            "no instance is created before the start date")
        expect(!HomeDailyTodoPolicy.shouldGenerateInstance(startDate: dayOne, isPaused: true, on: dayOne, calendar: calendar),
            "a paused rule does not generate an instance")
        expect(HomeDailyTodoPolicy.shouldGenerateInstance(startDate: dayOne, isPaused: false, on: dayTwo, calendar: calendar),
            "an active rule generates on and after its start date")

        let scheduled = HomeDailyTodoPolicy.scheduledAt(on: dayTwo, using: start, calendar: calendar)
        expect(scheduled == date(2026, 11, 11, 20, 15, calendar: calendar), "daily instances reuse the rule's local time")
        let started = date(2026, 11, 10, 23, 30, calendar: calendar)
        let resumedAt = date(2026, 11, 12, 8, 0, calendar: calendar)
        expect(HomeDailyTodoPolicy.elapsedThroughDailyMidnight(from: started, dailyDate: dayOne, now: resumedAt, calendar: calendar) == 1_800,
            "a timer restored after multiple days closes at its own day's midnight")
        expect(HomeDailyTodoPolicy.elapsedThroughDailyMidnight(from: date(2026, 11, 10, 12, 0, calendar: calendar), dailyDate: dayOne, now: date(2026, 11, 10, 10, 0, calendar: calendar), calendar: calendar) == nil,
            "a timer that started later is not counted before it began")

        let completionTime = date(2026, 11, 11, 20, 15, calendar: calendar)
        let plannedTime = date(2026, 11, 11, 8, 0, calendar: calendar)
        let completionLabel = HomeTodoSchedulePresentation.label(
            isCompleted: true,
            completedAt: completionTime,
            scheduledAt: plannedTime,
            now: dayTwo,
            calendar: calendar
        )
        expect(completionLabel.contains(completionTime.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))),
            "completed items show the actual completion time")
        expect(!completionLabel.contains(plannedTime.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))),
            "completed items do not show the planned time as their completion time")
        expect(HomeTodoSchedulePresentation.label(
            isCompleted: true,
            completedAt: nil,
            scheduledAt: plannedTime,
            now: dayTwo,
            calendar: calendar
        ) == "已完成", "legacy completed items without a timestamp remain understandable")
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
