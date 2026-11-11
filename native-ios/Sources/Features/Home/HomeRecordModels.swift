import Foundation
import SwiftData

struct HomeTodo: Identifiable, Hashable {
    let id: String
    var title: String
    var note: String
    var type: String
    var isCompleted: Bool
    var scheduledAt: Date
    var elapsedMilliseconds: Double
    var timerStartedAt: Date?
    var createdAt: Date
    var completedAt: Date?
    var dailyTimes: [String: Double]
    var dailyRuleID: String? = nil
    var dailyDate: Date? = nil
    var isSkipped = false
    var isDeletedForDay = false

    var subjectName: String {
        switch type {
        case "ziliao": "资料"
        case "panduan": "判断"
        case "shuliang": "数量"
        case "changshi": "常识"
        case "zhengzhi": "政治"
        case "shenlun": "申论"
        default: "言语"
        }
    }

    var subjectMark: String { String(subjectName.prefix(1)) }
}

struct HomeSticky: Identifiable, Hashable {
    let id: String
    var content: String
    var tag: String
    var colorHex: String
    var isPinned: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct HomeCountdown: Identifiable, Hashable {
    let id: String
    var name: String
    var date: Date
}

struct HomeErrorStats: Codable, Equatable, Sendable {
    var total: Int
    var unmastered: Int
    var weekNew: Int

    static let empty = HomeErrorStats(total: 0, unmastered: 0, weekNew: 0)
}

enum HomeErrorStatsRepository {
    static let recordID = "native.home.errorStats"

    static func cached(from records: [StoredRecord]) -> HomeErrorStats? {
        guard
            let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }),
            let value = record.jsonObject?["value"]
        else { return nil }
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder().decode(HomeErrorStats.self, from: data)
    }

    static func rebuild(in container: ModelContainer) async throws -> HomeErrorStats {
        try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = FetchDescriptor<StoredRecord>(
                predicate: #Predicate { $0.collection == "errors" }
            )
            let errors = try context.fetch(descriptor)
            let stats = calculate(from: errors)
            let value: [String: Any] = [
                "total": stats.total,
                "unmastered": stats.unmastered,
                "weekNew": stats.weekNew
            ]
            let payload = try JSONSerialization.data(withJSONObject: [
                "key": recordID,
                "value": value
            ], options: [.sortedKeys])
            let cachedDescriptor = FetchDescriptor<StoredRecord>(
                predicate: #Predicate { $0.collection == "keyvalue" && $0.recordID == recordID }
            )
            if let existing = try context.fetch(cachedDescriptor).first {
                existing.replacePayload(payload)
                existing.updatedAt = .now
            } else {
                context.insert(StoredRecord(
                    collection: "keyvalue",
                    recordID: recordID,
                    payload: payload,
                    updatedAt: .now
                ))
            }
            try context.save()
            return stats
        }.value
    }

    static func calculate(from records: [StoredRecord], now: Date = .now) -> HomeErrorStats {
        let weekInterval = Calendar.current.dateInterval(of: .weekOfYear, for: now)
        var unmastered = 0
        var weekNew = 0
        for record in records where record.collection == "errors" {
            if (record.jsonObject?["status"] as? String) != "已掌握" { unmastered += 1 }
            if let createdAt = record.createdAt, weekInterval?.contains(createdAt) == true { weekNew += 1 }
        }
        return HomeErrorStats(total: records.lazy.filter { $0.collection == "errors" }.count, unmastered: unmastered, weekNew: weekNew)
    }
}

struct HomeTodoType: Identifiable, Hashable {
    let key: String
    let title: String
    var id: String { key }
}

struct HomeDailyTodoRule: Identifiable, Hashable {
    let id: String
    var title: String
    var type: String
    var startDate: Date
    var scheduledTime: Date
    var isPaused: Bool
    var createdAt: Date
    var updatedAt: Date

    var typeName: String {
        HomeRecordRepository.todoTypes.first(where: { $0.key == type })?.title ?? "言语"
    }
}

enum HomeRecordRepository {
    static let todoTypes: [HomeTodoType] = [
        .init(key: "yanyu", title: "言语"), .init(key: "ziliao", title: "资料"),
        .init(key: "panduan", title: "判断"), .init(key: "shuliang", title: "数量"),
        .init(key: "changshi", title: "常识"), .init(key: "zhengzhi", title: "政治"),
        .init(key: "shenlun", title: "申论")
    ]

    static let stickyColors = ["#FFFBEB", "#EFF6FF", "#F0FDF4", "#FFF1F2", "#F5F3FF", "#FFFFFF"]

    static func todos(from records: [StoredRecord], includingDeleted: Bool = false) -> [HomeTodo] {
        records.compactMap { record in
            guard record.collection == "todos", let object = record.jsonObject else { return nil }
            let createdAt = date(object["createdAt"]) ?? record.createdAt ?? .distantPast
            return HomeTodo(
                id: record.recordID,
                title: string(object["text"]) ?? string(object["title"]) ?? "未命名待办",
                note: string(object["note"]) ?? "",
                type: normalizedTodoType(string(object["type"])),
                isCompleted: bool(object["completed"]),
                scheduledAt: date(object["scheduleDate"]) ?? createdAt,
                elapsedMilliseconds: number(object["elapsedMs"]),
                timerStartedAt: dateFromMilliseconds(object["timerStartedAt"]),
                createdAt: createdAt,
                completedAt: date(object["completedAt"]),
                dailyTimes: numberDictionary(object["dailyTimes"]),
                dailyRuleID: string(object["dailyRuleID"]),
                dailyDate: date(object["dailyDate"]),
                isSkipped: bool(object["isSkipped"]),
                isDeletedForDay: bool(object["isDeletedForDay"])
            )
        }
        .filter { includingDeleted || !$0.isDeletedForDay }
        .sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.createdAt > $1.createdAt
        }
    }

    static func dailyRules(from records: [StoredRecord]) -> [HomeDailyTodoRule] {
        records.compactMap { record in
            guard record.collection == "daily_todo_rules", let object = record.jsonObject,
                  let startDate = date(object["startDate"]) else { return nil }
            let createdAt = date(object["createdAt"]) ?? record.createdAt ?? .distantPast
            return HomeDailyTodoRule(
                id: record.recordID,
                title: string(object["title"]) ?? "未命名待办",
                type: normalizedTodoType(string(object["type"])),
                startDate: startDate,
                scheduledTime: date(object["scheduleTime"]) ?? startDate,
                isPaused: bool(object["isPaused"]),
                createdAt: createdAt,
                updatedAt: date(object["updatedAt"]) ?? record.updatedAt ?? createdAt
            )
        }
        .sorted { $0.createdAt > $1.createdAt }
    }

    static func stickies(from records: [StoredRecord]) -> [HomeSticky] {
        records.compactMap { record in
            guard record.collection == "stickies", let object = record.jsonObject else { return nil }
            let createdAt = date(object["createdAt"]) ?? record.createdAt ?? .distantPast
            return HomeSticky(
                id: record.recordID,
                content: string(object["content"]) ?? "",
                tag: string(object["tag"]) ?? "",
                colorHex: string(object["color"]) ?? "#FFFFFF",
                isPinned: bool(object["pinned"]),
                createdAt: createdAt,
                updatedAt: date(object["updatedAt"]) ?? record.updatedAt ?? createdAt
            )
        }
        .sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }

    static func countdowns(from records: [StoredRecord]) -> [HomeCountdown] {
        guard
            let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == "legacy.countdown" }),
            let value = record.jsonObject?["value"] as? [[String: Any]]
        else { return [] }

        return value.compactMap { item in
            guard let name = string(item["name"]), let date = date(item["date"]) else { return nil }
            return HomeCountdown(id: string(item["id"]) ?? makeID(prefix: "cd"), name: name, date: date)
        }
    }

    static func save(todo: HomeTodo, records: [StoredRecord], context: ModelContext) throws {
        let now = Date()
        let record = records.first { $0.collection == "todos" && $0.recordID == todo.id }
        let object = todoObject(todo, existing: record, updatedAt: now)
        try upsert(collection: "todos", id: todo.id, object: object, createdAt: todo.createdAt, updatedAt: now, existing: record, context: context)
    }

    static func saveDailyRuleAndReconcileToday(
        rule: HomeDailyTodoRule,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "todos" || $0.collection == "daily_todo_rules" }
        )
        let stored = try context.fetch(descriptor)
        let ruleRecord = stored.first { $0.collection == "daily_todo_rules" && $0.recordID == rule.id }
        let today = calendar.startOfDay(for: now)
        let instanceID = HomeDailyTodoPolicy.instanceID(ruleID: rule.id, on: today, calendar: calendar)
        let existingInstance = stored.first { $0.collection == "todos" && $0.recordID == instanceID }
        let canGenerateToday = HomeDailyTodoPolicy.shouldGenerateInstance(
            startDate: rule.startDate,
            isPaused: rule.isPaused,
            on: today,
            calendar: calendar
        )
        var ruleObject = ruleRecord?.jsonObject ?? [:]
        ruleObject["id"] = rule.id
        ruleObject["title"] = rule.title
        ruleObject["type"] = rule.type
        ruleObject["startDate"] = isoString(rule.startDate)
        ruleObject["scheduleTime"] = isoString(rule.scheduledTime)
        ruleObject["isPaused"] = rule.isPaused
        ruleObject["createdAt"] = isoString(rule.createdAt)
        ruleObject["updatedAt"] = isoString(now)

        try context.transaction {
            try write(
                collection: "daily_todo_rules",
                id: rule.id,
                object: ruleObject,
                createdAt: rule.createdAt,
                updatedAt: now,
                existing: ruleRecord,
                context: context
            )

            if let existingInstance,
               let storedTodo = todos(from: [existingInstance], includingDeleted: true).first,
               !storedTodo.isCompleted,
               !storedTodo.isDeletedForDay {
                var updated = storedTodo
                updated.title = rule.title
                updated.type = rule.type
                updated.scheduledAt = HomeDailyTodoPolicy.scheduledAt(
                    on: today,
                    using: rule.scheduledTime,
                    calendar: calendar
                ) ?? storedTodo.scheduledAt
                let object = todoObject(updated, existing: existingInstance, updatedAt: now)
                try write(
                    collection: "todos",
                    id: updated.id,
                    object: object,
                    createdAt: updated.createdAt,
                    updatedAt: now,
                    existing: existingInstance,
                    context: context
                )
            } else if existingInstance == nil,
                      canGenerateToday,
                      let scheduledAt = HomeDailyTodoPolicy.scheduledAt(
                        on: today,
                        using: rule.scheduledTime,
                        calendar: calendar
                      ) {
                let todo = HomeTodo(
                    id: instanceID,
                    title: rule.title,
                    note: "",
                    type: rule.type,
                    isCompleted: false,
                    scheduledAt: scheduledAt,
                    elapsedMilliseconds: 0,
                    timerStartedAt: nil,
                    createdAt: now,
                    completedAt: nil,
                    dailyTimes: [:],
                    dailyRuleID: rule.id,
                    dailyDate: today,
                    isSkipped: false
                )
                let object = todoObject(todo, existing: nil, updatedAt: now)
                try write(
                    collection: "todos",
                    id: instanceID,
                    object: object,
                    createdAt: now,
                    updatedAt: now,
                    existing: nil,
                    context: context
                )
            }
        }
    }

    static func deleteDailyTodoForToday(
        _ todo: HomeTodo,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        guard todo.dailyRuleID != nil,
              let dailyDate = todo.dailyDate,
              calendar.isDate(dailyDate, inSameDayAs: now) else { return }
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "todos" && $0.recordID == todo.id }
        )
        guard let record = try context.fetch(descriptor).first,
              var current = todos(from: [record], includingDeleted: true).first,
              !current.isDeletedForDay else { return }
        stopTimer(&current, now: now, calendar: calendar)
        current.isDeletedForDay = true
        let object = todoObject(current, existing: record, updatedAt: now)
        try context.transaction {
            try write(
                collection: "todos",
                id: current.id,
                object: object,
                createdAt: current.createdAt,
                updatedAt: now,
                existing: record,
                context: context
            )
        }
    }

    static func deleteDailyRule(
        id: String,
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "todos" || $0.collection == "daily_todo_rules" }
        )
        let stored = try context.fetch(descriptor)
        guard let ruleRecord = stored.first(where: { $0.collection == "daily_todo_rules" && $0.recordID == id }) else { return }
        let today = calendar.startOfDay(for: now)
        let todayID = HomeDailyTodoPolicy.instanceID(ruleID: id, on: today, calendar: calendar)
        let todayRecord = stored.first { $0.collection == "todos" && $0.recordID == todayID }
        try context.transaction {
            if let todayRecord,
               var todo = todos(from: [todayRecord], includingDeleted: true).first,
               !todo.isCompleted,
               !todo.isDeletedForDay {
                stopTimer(&todo, now: now, calendar: calendar)
                todo.isDeletedForDay = true
                try write(
                    collection: "todos",
                    id: todo.id,
                    object: todoObject(todo, existing: todayRecord, updatedAt: now),
                    createdAt: todo.createdAt,
                    updatedAt: now,
                    existing: todayRecord,
                    context: context
                )
            }
            context.delete(ruleRecord)
        }
    }

    static func save(rule: HomeDailyTodoRule, records: [StoredRecord], context: ModelContext) throws {
        let now = Date()
        let record = records.first { $0.collection == "daily_todo_rules" && $0.recordID == rule.id }
        var object = record?.jsonObject ?? [:]
        object["id"] = rule.id
        object["title"] = rule.title
        object["type"] = rule.type
        object["startDate"] = isoString(rule.startDate)
        object["scheduleTime"] = isoString(rule.scheduledTime)
        object["isPaused"] = rule.isPaused
        object["createdAt"] = isoString(rule.createdAt)
        object["updatedAt"] = isoString(now)
        try upsert(collection: "daily_todo_rules", id: rule.id, object: object, createdAt: rule.createdAt, updatedAt: now, existing: record, context: context)
    }

    static func ensureDailyTodoInstances(
        context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws {
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "todos" || $0.collection == "daily_todo_rules" }
        )
        let stored = try context.fetch(descriptor)
        let todoRecords = stored.filter { $0.collection == "todos" }
        let ruleRecords = stored.filter { $0.collection == "daily_todo_rules" }
        let today = calendar.startOfDay(for: now)

        for var todo in todos(from: todoRecords, includingDeleted: true) {
            guard let dailyDate = todo.dailyDate,
                  calendar.startOfDay(for: dailyDate) < today,
                  let startedAt = todo.timerStartedAt,
                  let elapsed = HomeDailyTodoPolicy.elapsedThroughDailyMidnight(
                    from: startedAt,
                    dailyDate: dailyDate,
                    now: now,
                    calendar: calendar
                  ) else { continue }
            let milliseconds = elapsed * 1_000
            todo.elapsedMilliseconds += milliseconds
            todo.dailyTimes[dayKey(dailyDate), default: 0] += milliseconds
            todo.timerStartedAt = nil
            try save(todo: todo, records: stored, context: context)
        }

        var existingIDs = Set(todoRecords.map(\.recordID))
        for rule in dailyRules(from: ruleRecords) {
            guard HomeDailyTodoPolicy.shouldGenerateInstance(
                startDate: rule.startDate,
                isPaused: rule.isPaused,
                on: today,
                calendar: calendar
            ) else { continue }
            let instanceID = HomeDailyTodoPolicy.instanceID(ruleID: rule.id, on: today, calendar: calendar)
            guard existingIDs.insert(instanceID).inserted,
                  let scheduledAt = HomeDailyTodoPolicy.scheduledAt(on: today, using: rule.scheduledTime, calendar: calendar)
            else { continue }
            let todo = HomeTodo(
                id: instanceID,
                title: rule.title,
                note: "",
                type: rule.type,
                isCompleted: false,
                scheduledAt: scheduledAt,
                elapsedMilliseconds: 0,
                timerStartedAt: nil,
                createdAt: now,
                completedAt: nil,
                dailyTimes: [:],
                dailyRuleID: rule.id,
                dailyDate: today,
                isSkipped: false
            )
            try save(todo: todo, records: stored, context: context)
        }
    }

    static func save(sticky: HomeSticky, records: [StoredRecord], context: ModelContext) throws {
        let now = Date()
        let record = records.first { $0.collection == "stickies" && $0.recordID == sticky.id }
        var object = record?.jsonObject ?? [:]
        object["id"] = sticky.id
        object["content"] = sticky.content
        object["tag"] = sticky.tag
        object["color"] = sticky.colorHex
        object["pinned"] = sticky.isPinned
        object["createdAt"] = isoString(sticky.createdAt)
        object["updatedAt"] = isoString(now)
        try upsert(collection: "stickies", id: sticky.id, object: object, createdAt: sticky.createdAt, updatedAt: now, existing: record, context: context)
    }

    static func save(countdowns: [HomeCountdown], records: [StoredRecord], context: ModelContext) throws {
        let record = records.first { $0.collection == "keyvalue" && $0.recordID == "legacy.countdown" }
        let value = countdowns.map { ["id": $0.id, "name": $0.name, "date": dayString($0.date)] }
        let object: [String: Any] = ["key": "legacy.countdown", "value": value]
        try upsert(collection: "keyvalue", id: "legacy.countdown", object: object, createdAt: nil, updatedAt: Date(), existing: record, context: context)
    }

    static func remove(collection: String, id: String, records: [StoredRecord], context: ModelContext) throws {
        guard let record = records.first(where: { $0.collection == collection && $0.recordID == id }) else { return }
        context.delete(record)
        try context.save()
    }

    static func makeTodo(title: String, note: String, type: String, scheduledAt: Date) -> HomeTodo {
        HomeTodo(
            id: makeID(prefix: "todo"), title: title, note: note, type: type,
            isCompleted: false, scheduledAt: scheduledAt, elapsedMilliseconds: 0,
            timerStartedAt: nil, createdAt: .now, completedAt: nil, dailyTimes: [:],
            dailyRuleID: nil, dailyDate: nil, isSkipped: false
        )
    }

    static func makeDailyRule(title: String, type: String, startAndTime: Date, id: String? = nil) -> HomeDailyTodoRule {
        let now = Date()
        return HomeDailyTodoRule(
            id: id ?? makeID(prefix: "daily-rule"),
            title: title,
            type: normalizedTodoType(type),
            startDate: Calendar.current.startOfDay(for: startAndTime),
            scheduledTime: startAndTime,
            isPaused: false,
            createdAt: now,
            updatedAt: now
        )
    }

    static func makeSticky(content: String, tag: String, colorHex: String, isPinned: Bool) -> HomeSticky {
        HomeSticky(
            id: makeID(prefix: "sticky"), content: content, tag: tag, colorHex: colorHex,
            isPinned: isPinned, createdAt: .now, updatedAt: .now
        )
    }

    static func makeCountdown(name: String, date: Date) -> HomeCountdown {
        HomeCountdown(id: makeID(prefix: "cd"), name: name, date: date)
    }

    static func chineseDate(_ date: Date, includeYear: Bool = true) -> String {
        let values = Calendar.current.dateComponents([.year, .month, .day], from: date)
        if includeYear { return "\(values.year ?? 0)年\(values.month ?? 0)月\(values.day ?? 0)日" }
        return "\(values.month ?? 0)月\(values.day ?? 0)日"
    }

    static func daysRemaining(until date: Date) -> Int {
        Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: .now),
            to: Calendar.current.startOfDay(for: date)
        ).day ?? 0
    }

    static func durationText(milliseconds: Double, startedAt: Date?, now: Date = .now) -> String {
        let running = startedAt.map { max(0, now.timeIntervalSince($0) * 1_000) } ?? 0
        let seconds = Int((milliseconds + running) / 1_000)
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }

    static func dayKey(_ date: Date) -> String { dayString(date) }

    private static func upsert(
        collection: String,
        id: String,
        object: [String: Any],
        createdAt: Date?,
        updatedAt: Date?,
        existing: StoredRecord?,
        context: ModelContext
    ) throws {
        try write(
            collection: collection,
            id: id,
            object: object,
            createdAt: createdAt,
            updatedAt: updatedAt,
            existing: existing,
            context: context
        )
        try context.save()
    }

    private static func write(
        collection: String,
        id: String,
        object: [String: Any],
        createdAt: Date?,
        updatedAt: Date?,
        existing: StoredRecord?,
        context: ModelContext
    ) throws {
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let existing {
            existing.replacePayload(payload)
            existing.createdAt = createdAt ?? existing.createdAt
            existing.updatedAt = updatedAt
        } else {
            context.insert(StoredRecord(collection: collection, recordID: id, payload: payload, createdAt: createdAt, updatedAt: updatedAt))
        }
    }

    private static func todoObject(_ todo: HomeTodo, existing: StoredRecord?, updatedAt: Date) -> [String: Any] {
        var object = existing?.jsonObject ?? [:]
        object["id"] = todo.id
        object["text"] = todo.title
        object["note"] = todo.note
        object["type"] = todo.type
        object["completed"] = todo.isCompleted
        object["status"] = todo.isCompleted ? "completed" : "pending"
        object["scheduleDate"] = isoString(todo.scheduledAt)
        object["elapsedMs"] = todo.elapsedMilliseconds
        object["timerStartedAt"] = todo.timerStartedAt.map { $0.timeIntervalSince1970 * 1_000 } ?? NSNull()
        object["createdAt"] = isoString(todo.createdAt)
        object["updatedAt"] = isoString(updatedAt)
        object["completedAt"] = todo.completedAt.map(isoString) ?? NSNull()
        object["dailyTimes"] = todo.dailyTimes
        object["isSkipped"] = todo.isSkipped
        object["isDeletedForDay"] = todo.isDeletedForDay
        if let dailyRuleID = todo.dailyRuleID {
            object["dailyRuleID"] = dailyRuleID
            object["dailyDate"] = todo.dailyDate.map(isoString) ?? isoString(Calendar.current.startOfDay(for: todo.scheduledAt))
        } else {
            object.removeValue(forKey: "dailyRuleID")
            object.removeValue(forKey: "dailyDate")
        }
        return object
    }

    private static func stopTimer(_ todo: inout HomeTodo, now: Date, calendar: Calendar) {
        guard let startedAt = todo.timerStartedAt else { return }
        let end = min(now, todo.dailyDate.flatMap { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) } ?? now)
        let milliseconds = max(0, end.timeIntervalSince(startedAt) * 1_000)
        todo.elapsedMilliseconds += milliseconds
        if let dailyDate = todo.dailyDate {
            todo.dailyTimes[dayKey(dailyDate), default: 0] += milliseconds
        }
        todo.timerStartedAt = nil
    }

    private static func string(_ value: Any?) -> String? { value as? String }
    private static func bool(_ value: Any?) -> Bool { (value as? Bool) ?? (value as? NSNumber)?.boolValue ?? false }
    private static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? (value as? Double) ?? 0 }
    private static func numberDictionary(_ value: Any?) -> [String: Double] {
        guard let source = value as? [String: Any] else { return [:] }
        return source.reduce(into: [:]) { result, entry in result[entry.key] = number(entry.value) }
    }

    private static func normalizedTodoType(_ value: String?) -> String {
        guard let value else { return "yanyu" }
        if todoTypes.contains(where: { $0.key == value }) { return value }
        return "yanyu"
    }

    private static func date(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let date = value as? Date { return date }
        if let number = value as? NSNumber { return dateFromMilliseconds(number) }
        guard let string = value as? String, !string.isEmpty else { return nil }
        if let date = dayFormatter.date(from: string) { return date }
        return fractionalFormatter.date(from: string) ?? ISO8601DateFormatter().date(from: string)
    }

    private static func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let number = value as? NSNumber else { return nil }
        let raw = number.doubleValue
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }

    private static let fractionalFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func isoString(_ date: Date) -> String { fractionalFormatter.string(from: date) }
    private static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    private static func makeID(prefix: String) -> String { "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))" }
}
