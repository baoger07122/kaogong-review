import Foundation
import SwiftData

extension LibraryReviewSource {
    static func classify(_ record: StoredRecord, records: [StoredRecord]) -> LibraryReviewSource {
        let metadata = record.reviewSourceMetadata
        let linkedExam: [String: Any]?
        if let examID = metadata["sourceExamId"] as? String,
           let exam = records.first(where: { $0.collection == "exams" && $0.recordID == examID }) {
            linkedExam = exam.reviewSourceMetadata
        } else {
            linkedExam = nil
        }
        return LibraryReviewSourcePolicy.classify(
            collection: record.collection,
            object: metadata,
            linkedExamObject: linkedExam
        )
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
                        if LibraryReviewSource.explicitValue(in: exam.reviewSourceMetadata) != source {
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
