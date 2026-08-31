import Foundation

enum LibraryContentKind: String, CaseIterable, Identifiable {
    case errors = "错题"
    case notes = "笔记"
    case stickies = "便签"
    case words = "词语库"

    var id: String { rawValue }

    var collection: String {
        switch self {
        case .errors: "errors"
        case .notes: "notes"
        case .stickies: "stickies"
        case .words: "words"
        }
    }

    var emptyTitle: String {
        switch self {
        case .errors: "还没有错题"
        case .notes: "还没有笔记"
        case .stickies: "这个模块还没有便签"
        case .words: "还没有词语记录"
        }
    }

    var emptyDetail: String {
        switch self {
        case .errors: "当前范围内还没有收录错题"
        case .notes: "当前范围内还没有记录笔记"
        case .stickies: "便签只保存在当前模块内"
        case .words: "词语库仅属于言语理解的逻辑填空模块"
        }
    }
}

enum LibraryCardSize: String, CaseIterable, Identifiable {
    case small = "小"
    case medium = "中"
    case large = "大"

    var id: String { rawValue }
    var columnCount: Int {
        switch self {
        case .small: 3
        case .medium: 2
        case .large: 1
        }
    }
}

struct LibraryScope: Equatable {
    var subject: String?
    var module: String?

    var isAll: Bool { subject == nil }
    var hasModuleContext: Bool {
        guard let subject else { return false }
        return module != nil || subject == "资料分析"
    }
    var isLogicFill: Bool { subject == "言语理解" && module == "逻辑填空" }

    var title: String {
        if let module { return module }
        if let subject { return subject }
        return "全部"
    }

    func contains(_ record: StoredRecord) -> Bool {
        guard let subject else { return true }
        guard record.subject == subject else { return false }
        guard let module else { return true }
        return record.module == module
    }
}

struct LibraryRecordSnapshot: Identifiable {
    let record: StoredRecord
    let title: String
    let summary: String
    let tags: [String]
    let status: String?
    let createdAt: Date?
    let colorHex: String?
    let isPinned: Bool

    var id: String { record.compoundID }

    init(record: StoredRecord) {
        self.record = record
        let object = record.jsonObject ?? [:]
        title = Self.firstText(in: object, keys: ["title", "question", "name", "words", "text", "content"])
            .map(Self.plainText) ?? "未命名记录"
        summary = Self.firstText(
            in: object,
            keys: ["content", "note", "errorNote", "meaning", "myUnderstanding", "relation", "coreDifference", "question"]
        ).map(Self.plainText) ?? ""
        status = Self.firstText(in: object, keys: ["status", "masteryStatus"])
        colorHex = Self.firstText(in: object, keys: ["color", "colorHex"])
        isPinned = (object["pinned"] as? Bool) ?? (object["pinned"] as? NSNumber)?.boolValue ?? false
        createdAt = record.createdAt ?? Self.date(in: object, keys: ["createdAt", "date", "updatedAt"])

        var values: [String] = []
        if let type = Self.firstText(in: object, keys: ["type", "category", "errorCause"]) { values.append(type) }
        if let points = object["knowledgePoints"] as? [String] { values.append(contentsOf: points) }
        if let point = Self.firstText(in: object, keys: ["knowledgePoint"]) { values.append(point) }
        tags = Array(values.filter { !$0.isEmpty }.prefix(3))
    }

    private static func firstText(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let text = object[key] as? String, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return text
            }
        }
        return nil
    }

    private static func plainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func date(in object: [String: Any], keys: [String]) -> Date? {
        let iso = ISO8601DateFormatter()
        for key in keys {
            if let value = object[key] as? String, let date = iso.date(from: value) { return date }
            if let value = object[key] as? Double { return Date(timeIntervalSince1970: value > 10_000_000_000 ? value / 1000 : value) }
        }
        return nil
    }
}
