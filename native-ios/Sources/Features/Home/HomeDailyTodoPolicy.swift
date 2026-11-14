import Foundation

struct HomeDailyTodoRuleOrderEntry: Equatable {
    let id: String
    let sortOrder: Int?
    let createdAt: Date
}

struct HomeDailyTodoInstanceNoteEdit: Equatable {
    let instanceID: String
    let ruleID: String
    let dailyDate: Date
    let note: String
}

enum HomeDailyTodoInstanceNoteEditError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        "今日待办实例已变化或被删除，备注未保存。请保留草稿并重新打开待办后再试。"
    }
}

enum HomeDailyTodoRuleOrderError: LocalizedError {
    case stale

    var errorDescription: String? {
        "每日待办列表已变化，排序未保存。请重新打开排序后再试。"
    }
}

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

    static func orderedRuleIDs(_ entries: [HomeDailyTodoRuleOrderEntry]) -> [String] {
        entries.enumerated().sorted { lhs, rhs in
            switch (lhs.element.sortOrder, rhs.element.sortOrder) {
            case let (left?, right?) where left != right:
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                if lhs.element.createdAt != rhs.element.createdAt {
                    return lhs.element.createdAt > rhs.element.createdAt
                }
                return lhs.offset < rhs.offset
            }
        }.map(\.element.id)
    }

    static func sortOrderForNewRule(existingOrders: [Int?]) -> Int {
        let minimum = existingOrders.compactMap { $0 }.min() ?? 0
        return minimum == Int.min ? Int.min : minimum - 1
    }

    static func isValidRuleOrder(existingIDs: [String], proposedIDs: [String]) -> Bool {
        guard existingIDs.count == proposedIDs.count,
              Set(existingIDs).count == existingIDs.count,
              Set(proposedIDs).count == proposedIDs.count else { return false }
        return Set(existingIDs) == Set(proposedIDs)
    }

    static func reorderingRecurringTodoSlots<Item>(
        _ items: [Item],
        ruleOrder: [String],
        isCompleted: (Item) -> Bool,
        ruleID: (Item) -> String?
    ) -> [Item] {
        let positions = items.indices.filter { index in
            guard !isCompleted(items[index]), let id = ruleID(items[index]) else { return false }
            return ruleOrder.contains(id)
        }
        let orderedItems = positions.map { items[$0] }.sorted { left, right in
            let leftID = ruleID(left) ?? ""
            let rightID = ruleID(right) ?? ""
            return (ruleOrder.firstIndex(of: leftID) ?? .max) < (ruleOrder.firstIndex(of: rightID) ?? .max)
        }
        var result = items
        for (position, item) in zip(positions, orderedItems) {
            result[position] = item
        }
        return result
    }

    static func validatesInstanceNoteEdit(
        _ edit: HomeDailyTodoInstanceNoteEdit,
        currentRuleID: String,
        storedInstanceID: String?,
        storedRuleID: String?,
        storedDailyDate: Date?,
        isDeletedForDay: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        guard !isDeletedForDay,
              edit.ruleID == currentRuleID,
              edit.instanceID == instanceID(ruleID: currentRuleID, on: edit.dailyDate, calendar: calendar),
              storedInstanceID == edit.instanceID,
              storedRuleID == currentRuleID,
              let storedDailyDate,
              calendar.isDate(storedDailyDate, inSameDayAs: edit.dailyDate),
              calendar.isDate(edit.dailyDate, inSameDayAs: now) else { return false }
        return true
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
