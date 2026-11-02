import Foundation
import SwiftData

enum LibraryReviewSource: String, CaseIterable, Identifiable, Codable, Hashable {
    case real = "real"
    case mock = "mock"
    case pending = "pending"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .real: "真题复盘"
        case .mock: "模拟题复盘"
        case .pending: "待确认"
        }
    }

    static func explicitValue(in object: [String: Any]) -> LibraryReviewSource? {
        for key in ["reviewSource", "examType", "paperType", "sourceType"] {
            if let value = object[key] as? String, let source = explicitValue(value) { return source }
        }
        if let value = object["type"] as? String, let source = explicitValue(value) { return source }
        if let value = object["source"] as? String, let source = explicitValue(value) { return source }
        return nil
    }

    static func explicitValue(_ rawValue: String) -> LibraryReviewSource? {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "real", "true", "past", "真题", "历年真题", "真题卷": .real
        case "mock", "simulation", "simulated", "模拟", "模拟题", "模拟卷": .mock
        case "pending", "unknown", "unclassified", "未分类", "未确认", "待确认": .pending
        default: nil
        }
    }

    static func classify(_ record: StoredRecord, records: [StoredRecord]) -> LibraryReviewSource {
        if record.collection == "words" { return .pending }
        let object = record.indexObject ?? [:]
        if let source = explicitValue(in: object) { return source }

        if record.collection == "errors" {
            if let paperID = object["questionBankPaperID"] as? String, !paperID.isEmpty { return .real }
            if let examID = object["sourceExamId"] as? String,
               let exam = records.first(where: { $0.collection == "exams" && $0.recordID == examID }),
               let source = explicitValue(in: exam.indexObject ?? [:]) {
                return source
            }
        }
        return .pending
    }
}

enum LibraryReviewSourceRepository {
    static func assign(
        _ source: LibraryReviewSource,
        to recordsToUpdate: [StoredRecord],
        allRecords: [StoredRecord],
        context: ModelContext
    ) throws {
        let now = ISO8601DateFormatter().string(from: .now)
        try context.transaction {
            for record in recordsToUpdate where ["errors", "notes", "stickies"].contains(record.collection) {
                var object = record.jsonObject ?? [:]
                object["reviewSource"] = source.rawValue
                if record.collection == "errors",
                   let examID = object["sourceExamId"] as? String,
                   !examID.isEmpty {
                    if let exam = allRecords.first(where: { $0.collection == "exams" && $0.recordID == examID }) {
                        if LibraryReviewSource.explicitValue(in: exam.indexObject ?? [:]) != source {
                            object.removeValue(forKey: "sourceExamId")
                            var examObject = exam.jsonObject ?? [:]
                            let linkedIDs = Set(examObject["linkedErrorIds"] as? [String] ?? [])
                            examObject["linkedErrorIds"] = Array(linkedIDs.subtracting(Set([record.recordID]))).sorted()
                            examObject["updatedAt"] = now
                            exam.replacePayload(try JSONSerialization.data(withJSONObject: examObject, options: [.sortedKeys]))
                            exam.updatedAt = .now
                        }
                    } else {
                        object.removeValue(forKey: "sourceExamId")
                    }
                }
                object["updatedAt"] = now
                record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                record.updatedAt = .now
            }
        }
    }
}

enum LibraryMockExamMemory {
    private static let recordID = "library-last-mock-exam-selection-v1"

    static func selectedID(records: [StoredRecord]) -> String? {
        guard let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }),
              let value = record.jsonObject?["examID"] as? String else { return nil }
        return value
    }

    static func remember(_ examID: String, records: [StoredRecord], context: ModelContext) throws {
        let now = ISO8601DateFormatter().string(from: .now)
        let object = ["id": recordID, "examID": examID, "updatedAt": now]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
        }
    }
}
