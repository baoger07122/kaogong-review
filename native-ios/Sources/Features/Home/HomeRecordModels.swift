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

enum HomeRecordRepository {
    static let todoTypes: [HomeTodoType] = [
        .init(key: "yanyu", title: "言语"), .init(key: "ziliao", title: "资料"),
        .init(key: "panduan", title: "判断"), .init(key: "shuliang", title: "数量"),
        .init(key: "changshi", title: "常识"), .init(key: "zhengzhi", title: "政治"),
        .init(key: "shenlun", title: "申论")
    ]

    static let stickyColors = ["#FFFBEB", "#EFF6FF", "#F0FDF4", "#FFF1F2", "#F5F3FF", "#FFFFFF"]

    static func todos(from records: [StoredRecord]) -> [HomeTodo] {
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
                dailyTimes: numberDictionary(object["dailyTimes"])
            )
        }
        .sorted {
            if $0.isCompleted != $1.isCompleted { return !$0.isCompleted }
            return $0.createdAt > $1.createdAt
        }
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
        var object = record?.jsonObject ?? [:]
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
        object["updatedAt"] = isoString(now)
        object["completedAt"] = todo.completedAt.map(isoString) ?? NSNull()
        object["dailyTimes"] = todo.dailyTimes
        try upsert(collection: "todos", id: todo.id, object: object, createdAt: todo.createdAt, updatedAt: now, existing: record, context: context)
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
            timerStartedAt: nil, createdAt: .now, completedAt: nil, dailyTimes: [:]
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
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let existing {
            existing.replacePayload(payload)
            existing.createdAt = createdAt ?? existing.createdAt
            existing.updatedAt = updatedAt
        } else {
            context.insert(StoredRecord(collection: collection, recordID: id, payload: payload, createdAt: createdAt, updatedAt: updatedAt))
        }
        try context.save()
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
