import Combine
import Foundation
import SwiftData

struct LegacyRecordDraft: @unchecked Sendable {
    let collection: String
    let recordID: String
    let payload: Data
    let subject: String?
    let module: String?
    let createdAt: Date?
    let updatedAt: Date?

    var compoundID: String { "\(collection):\(recordID)" }
}

struct LegacyImportPackage: @unchecked Sendable {
    let version: Int
    let records: [LegacyRecordDraft]
    let counts: [String: Int]
}

struct LegacyImportSummary: Equatable {
    let version: Int
    let total: Int
    let counts: [String: Int]

    var message: String {
        let order = ["errors", "notes", "exams", "todos", "subject_reviews", "words", "stickies", "keyvalue"]
        let details = order.compactMap { key -> String? in
            guard let value = counts[key], value > 0 else { return nil }
            return "\(key) \(value)"
        }.joined(separator: " · ")
        return "已导入 \(total) 条记录" + (details.isEmpty ? "" : "（\(details)）")
    }
}

enum LegacyBackupImportError: LocalizedError {
    case invalidRoot
    case missingVersion
    case invalidCollection(String)
    case missingRecordID(String)
    case tooManyRecords(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "备份文件顶层不是 JSON 对象"
        case .missingVersion: "备份文件缺少有效 version"
        case .invalidCollection(let name): "备份字段 \(name) 不是数组"
        case .missingRecordID(let name): "\(name) 中存在缺少 id 的记录"
        case .tooManyRecords(let count): "备份包含 \(count) 条记录，超过单次迁移上限"
        }
    }
}

enum LegacyBackupImporter {
    private static let collectionMappings: [(backup: String, native: String)] = [
        ("errors", "errors"),
        ("notes", "notes"),
        ("exams", "exams"),
        ("todos", "todos"),
        ("subjectReviews", "subject_reviews"),
        ("words", "words"),
        ("stickies", "stickies")
    ]

    static func parse(data: Data) throws -> LegacyImportPackage {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LegacyBackupImportError.invalidRoot
        }
        guard let versionNumber = root["version"] as? NSNumber else {
            throw LegacyBackupImportError.missingVersion
        }

        var draftsByID: [String: LegacyRecordDraft] = [:]
        var counts: [String: Int] = [:]

        for mapping in collectionMappings {
            guard let raw = root[mapping.backup] else { continue }
            guard let items = raw as? [[String: Any]] else {
                throw LegacyBackupImportError.invalidCollection(mapping.backup)
            }
            for item in items {
                guard let id = item["id"] as? String, !id.isEmpty else {
                    throw LegacyBackupImportError.missingRecordID(mapping.backup)
                }
                let draft = try makeDraft(collection: mapping.native, id: id, object: item)
                draftsByID[draft.compoundID] = draft
            }
            counts[mapping.native] = items.count
        }

        try appendKeyValue(root["keyvalue"], drafts: &draftsByID, counts: &counts)
        try appendTopLevelValue(root["countdown"], key: "legacy.countdown", drafts: &draftsByID, counts: &counts)
        try appendTopLevelValue(root["noteTypes"], key: "legacy.noteTypes", drafts: &draftsByID, counts: &counts)
        try appendHomeErrorStats(drafts: &draftsByID, counts: &counts)

        guard draftsByID.count <= 100_000 else {
            throw LegacyBackupImportError.tooManyRecords(draftsByID.count)
        }

        return LegacyImportPackage(
            version: versionNumber.intValue,
            records: Array(draftsByID.values),
            counts: counts
        )
    }

    private static func appendKeyValue(
        _ raw: Any?,
        drafts: inout [String: LegacyRecordDraft],
        counts: inout [String: Int]
    ) throws {
        guard let raw else { return }
        var items: [[String: Any]] = []
        if let array = raw as? [[String: Any]] {
            items = array
        } else if let object = raw as? [String: Any] {
            items = object.map { ["key": $0.key, "value": $0.value] }
        } else {
            throw LegacyBackupImportError.invalidCollection("keyvalue")
        }

        for item in items {
            guard let key = item["key"] as? String, !key.isEmpty else {
                throw LegacyBackupImportError.missingRecordID("keyvalue")
            }
            if key.hasPrefix("auto_backup_") { continue }
            let draft = try makeDraft(collection: "keyvalue", id: key, object: item)
            drafts[draft.compoundID] = draft
        }
        counts["keyvalue", default: 0] = drafts.values.lazy.filter { $0.collection == "keyvalue" }.count
    }

    private static func appendTopLevelValue(
        _ value: Any?,
        key: String,
        drafts: inout [String: LegacyRecordDraft],
        counts: inout [String: Int]
    ) throws {
        guard let value else { return }
        let object: [String: Any] = ["key": key, "value": value]
        let draft = try makeDraft(collection: "keyvalue", id: key, object: object)
        drafts[draft.compoundID] = draft
        counts["keyvalue", default: 0] += 1
    }

    private static func makeDraft(collection: String, id: String, object: [String: Any]) throws -> LegacyRecordDraft {
        let object = normalizedObject(object, collection: collection, id: id)
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return LegacyRecordDraft(
            collection: collection,
            recordID: id,
            payload: payload,
            subject: object["subject"] as? String,
            module: object["module"] as? String,
            createdAt: parseDate(object["createdAt"]),
            updatedAt: parseDate(object["updatedAt"])
        )
    }

    private static func appendHomeErrorStats(
        drafts: inout [String: LegacyRecordDraft],
        counts: inout [String: Int]
    ) throws {
        let errors = drafts.values.filter { $0.collection == "errors" }
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: .now)
        var unmastered = 0
        var weekNew = 0
        for draft in errors {
            let object = (try? JSONSerialization.jsonObject(with: draft.payload)) as? [String: Any]
            if (object?["status"] as? String) != "已掌握" { unmastered += 1 }
            if let createdAt = draft.createdAt, week?.contains(createdAt) == true { weekNew += 1 }
        }
        let key = "native.home.errorStats"
        let object: [String: Any] = [
            "key": key,
            "value": ["total": errors.count, "unmastered": unmastered, "weekNew": weekNew]
        ]
        let draft = try makeDraft(collection: "keyvalue", id: key, object: object)
        drafts[draft.compoundID] = draft
        counts["keyvalue", default: 0] = drafts.values.lazy.filter { $0.collection == "keyvalue" }.count
    }

    private static func normalizedObject(_ source: [String: Any], collection: String, id: String) -> [String: Any] {
        var object = source
        object["id"] = object["id"] ?? id

        if collection == "errors" {
            if let subject = trimmedString(object["subject"]) { object["subject"] = subject }
            if let module = trimmedString(object["module"]) { object["module"] = module }
            if let question = object["question"] as? String { object["question"] = normalizedRichText(question) }
            if let note = object["note"] as? String { object["note"] = normalizedRichText(note) }

            let points: [String]
            if let values = object["knowledgePoints"] as? [String] {
                points = values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            } else if let value = trimmedString(object["knowledgePoint"]) {
                points = [value]
            } else {
                points = []
            }
            object["knowledgePoints"] = Array(points.prefix(20))
            object["knowledgePoint"] = points.first ?? ""
            object["errorCause"] = trimmedString(object["errorCause"]) ?? "待复盘"
            object["status"] = (object["status"] as? String) == "已掌握" ? "已掌握" : "未掌握"
            object["reviewCount"] = (object["reviewCount"] as? NSNumber)?.intValue ?? 0
        }

        return object
    }

    private static func normalizedRichText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedString(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
        }
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value) { return date }
        let day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.dateFormat = "yyyy-MM-dd"
        return day.date(from: value)
    }
}

enum LegacyBackupRestorer {
    static func replace(
        with package: LegacyImportPackage,
        in context: ModelContext,
        beforeSave: () throws -> Void = {}
    ) throws {
        let existing = try context.fetch(FetchDescriptor<StoredRecord>())
        existing.forEach(context.delete)
        for draft in package.records {
            context.insert(StoredRecord(
                collection: draft.collection,
                recordID: draft.recordID,
                payload: draft.payload,
                subject: draft.subject,
                module: draft.module,
                createdAt: draft.createdAt,
                updatedAt: draft.updatedAt
            ))
        }
        try beforeSave()
        try context.save()
    }
}

@MainActor
final class LegacyBackupImportCoordinator: ObservableObject {
    @Published private(set) var isImporting = false
    @Published private(set) var summary: LegacyImportSummary?
    @Published private(set) var errorMessage: String?

    func reportError(_ error: Error) {
        summary = nil
        errorMessage = error.localizedDescription
    }

    func clearMessages() {
        summary = nil
        errorMessage = nil
    }

    func importBackup(from url: URL, into context: ModelContext) {
        isImporting = true
        summary = nil
        errorMessage = nil

        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess { url.stopAccessingSecurityScopedResource() }
            isImporting = false
        }

        do {
            let data = try Data(contentsOf: url)
            let package = try LegacyBackupImporter.parse(data: data)
            try LegacyBackupRestorer.replace(with: package, in: context)
            summary = LegacyImportSummary(version: package.version, total: package.records.count, counts: package.counts)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }

    func importBackup(data: Data, container: ModelContainer) {
        isImporting = true
        summary = nil
        errorMessage = nil

        Task {
            do {
                let package = try await Task.detached(priority: .userInitiated) {
                    try LegacyBackupImporter.parse(data: data)
                }.value
                try await Task.detached(priority: .userInitiated) {
                    let importContext = ModelContext(container)
                    importContext.autosaveEnabled = false
                    try LegacyBackupRestorer.replace(with: package, in: importContext)
                }.value
                summary = LegacyImportSummary(version: package.version, total: package.records.count, counts: package.counts)
            } catch {
                errorMessage = error.localizedDescription
            }
            isImporting = false
        }
    }
}
