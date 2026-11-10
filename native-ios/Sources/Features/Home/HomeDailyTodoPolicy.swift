import Foundation

enum HomeDailyTodoPolicy {
    static func instanceID(ruleID: String, on date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return "\(ruleID)::\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    static func shouldGenerateInstance(
        startDate: Date,
        isPaused: Bool,
        on date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        !isPaused && calendar.startOfDay(for: startDate) <= calendar.startOfDay(for: date)
    }

    static func scheduledAt(on date: Date, using time: Date, calendar: Calendar = .current) -> Date? {
        var components = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        components.hour = timeComponents.hour
        components.minute = timeComponents.minute
        components.second = timeComponents.second
        return calendar.date(from: components)
    }

    static func elapsedThroughDailyMidnight(
        from startedAt: Date,
        dailyDate: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> TimeInterval? {
        let startOfDailyDate = calendar.startOfDay(for: dailyDate)
        guard let midnight = calendar.date(byAdding: .day, value: 1, to: startOfDailyDate) else { return nil }
        let end = min(midnight, now)
        guard startedAt < end else { return nil }
        return max(0, end.timeIntervalSince(startedAt))
    }
}

enum HomeTodoSchedulePresentation {
    static func label(
        isCompleted: Bool,
        completedAt: Date?,
        scheduledAt: Date,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> String {
        if isCompleted {
            guard let completedAt else { return "已完成" }
            let time = completedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
            if calendar.isDate(completedAt, inSameDayAs: now) { return "完成 \(time)" }
            return "完成 \(shortDate(completedAt))\n\(time)"
        }

        let time = scheduledAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
        if calendar.isDate(scheduledAt, inSameDayAs: now) { return time }
        return "\(shortDate(scheduledAt))\n\(time)"
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        return formatter.string(from: date)
    }
}
