import Combine
import Foundation
import SwiftData

struct LegacyRecordDraft {
    let collection: String
    let recordID: String
    let payload: Data
    let subject: String?
    let module: String?
    let createdAt: Date?
    let updatedAt: Date?

    var compoundID: String { "\(collection):\(recordID)" }
}

struct LegacyImportPackage {
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

    var errorDescription: String? {
        switch self {
        case .invalidRoot: "备份文件顶层不是 JSON 对象"
        case .missingVersion: "备份文件缺少有效 version"
        case .invalidCollection(let name): "备份字段 \(name) 不是数组"
        case .missingRecordID(let name): "\(name) 中存在缺少 id 的记录"
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
            let draft = try makeDraft(collection: "keyvalue", id: key, object: item)
            drafts[draft.compoundID] = draft
        }
        counts["keyvalue", default: 0] += items.count
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
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        return LegacyRecordDraft(
            collection: collection,
            recordID: id,
            payload: payload,
            subject: object["subject"] as? String,
            module: object["module"] as? String,
            createdAt: parseDate(object["createdAt"] as? String),
            updatedAt: parseDate(object["updatedAt"] as? String)
        )
    }

    private static func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
            try context.save()
            summary = LegacyImportSummary(version: package.version, total: package.records.count, counts: package.counts)
        } catch {
            context.rollback()
            errorMessage = error.localizedDescription
        }
    }
}
