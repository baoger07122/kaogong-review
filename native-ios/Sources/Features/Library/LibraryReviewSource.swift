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

final class LibraryReviewSourceClassificationCache {
    private struct Revision: Equatable {
        let identity: ObjectIdentifier
        let compoundID: String
        let collection: String
        let subject: String?
        let module: String?
        let updatedAt: Date?
        let payloadCount: Int
        let indexPayloadCount: Int

        init(_ record: StoredRecord) {
            identity = ObjectIdentifier(record)
            compoundID = record.compoundID
            collection = record.collection
            subject = record.subject
            module = record.module
            updatedAt = record.updatedAt
            payloadCount = record.payload.count
            indexPayloadCount = record.indexPayload?.count ?? 0
        }
    }

    private var revision: [Revision]?
    private var values: [String: LibraryReviewSource] = [:]

    func classifications(for records: [StoredRecord]) -> [String: LibraryReviewSource] {
        let currentRevision = records.map(Revision.init)
        guard revision != currentRevision else { return values }

        var examMetadata: [String: [String: Any]] = [:]
        for record in records where record.collection == "exams" {
            examMetadata[record.recordID] = record.reviewSourceMetadata
        }

        var result: [String: LibraryReviewSource] = [:]
        result.reserveCapacity(records.count)
        for record in records where record.collection != "exams" {
            let metadata = record.reviewSourceMetadata
            let linkedExam = (metadata["sourceExamId"] as? String).flatMap { examMetadata[$0] }
            result[record.compoundID] = LibraryReviewSourcePolicy.classify(
                collection: record.collection,
                object: metadata,
                linkedExamObject: linkedExam
            )
        }
        revision = currentRevision
        values = result
        return result
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
