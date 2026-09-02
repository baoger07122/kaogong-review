import Foundation
import SwiftData

struct ExamSubjectScore: Identifiable, Equatable {
    var subject: String
    var score: String
    var totalScore: String
    var id: String { subject }
}

struct ExamDraft {
    var original: [String: Any] = [:]
    var id = ""
    var name = ""
    var examDate = Date()
    var subjectScores: [ExamSubjectScore] = []
    var totalAccuracy = ""
    var totalTime = ""
    var targetScore = ""
    var reviewNote = ""
    var linkedErrorIDs: Set<String> = []

    init(record: StoredRecord? = nil) {
        original = record?.jsonObject ?? [:]
        id = record?.recordID ?? ""
        name = original["name"] as? String ?? ""
        if let value = original["examDate"] as? String { examDate = Self.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .now }
        if let values = original["subjectScores"] as? [[String: Any]] {
            subjectScores = values.compactMap {
                guard let subject = $0["subject"] as? String else { return nil }
                return ExamSubjectScore(subject: subject, score: Self.numberText($0["score"]), totalScore: Self.numberText($0["totalScore"]))
            }
        }
        totalAccuracy = Self.numberText(original["totalAccuracy"])
        totalTime = Self.numberText(original["totalTime"])
        targetScore = Self.numberText(original["targetScore"])
        reviewNote = original["reviewNote"] as? String ?? ""
        linkedErrorIDs = Set(original["linkedErrorIds"] as? [String] ?? [])
    }

    static let dayFormatter: DateFormatter = { let value = DateFormatter(); value.locale = Locale(identifier: "zh_CN"); value.dateFormat = "yyyy-MM-dd"; return value }()
    private static func numberText(_ value: Any?) -> String { if let number = value as? NSNumber { return number.stringValue }; return value as? String ?? "" }
}

enum ExamRepository {
    static func save(_ draft: ExamDraft, records: [StoredRecord], context: ModelContext) throws {
        let now = Date(); let id = draft.id.isEmpty ? "exam_\(Int(now.timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))" : draft.id
        let existing = records.first { $0.collection == "exams" && $0.recordID == id }
        var object = draft.original
        object["id"] = id; object["name"] = draft.name; object["examDate"] = ExamDraft.dayFormatter.string(from: draft.examDate)
        object["subjectScores"] = draft.subjectScores.map { ["subject": $0.subject, "score": Int($0.score) ?? 0, "totalScore": Int($0.totalScore) ?? 0] }
        object["totalAccuracy"] = Int(draft.totalAccuracy) ?? 0; object["totalTime"] = Int(draft.totalTime) ?? 0; object["targetScore"] = Int(draft.targetScore) ?? 0
        object["reviewNote"] = draft.reviewNote; object["linkedErrorIds"] = Array(draft.linkedErrorIDs); object["updatedAt"] = ISO8601DateFormatter().string(from: now)
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let existing { existing.replacePayload(payload); existing.updatedAt = now }
        else { context.insert(StoredRecord(collection: "exams", recordID: id, payload: payload, createdAt: now, updatedAt: now)) }

        for error in records where error.collection == "errors" {
            var errorObject = error.jsonObject ?? [:]
            let linked = draft.linkedErrorIDs.contains(error.recordID)
            let currentlyLinked = errorObject["sourceExamId"] as? String == id
            guard linked || currentlyLinked else { continue }
            if linked { errorObject["sourceExamId"] = id } else { errorObject.removeValue(forKey: "sourceExamId") }
            errorObject["updatedAt"] = ISO8601DateFormatter().string(from: now)
            error.replacePayload(try JSONSerialization.data(withJSONObject: errorObject, options: [.sortedKeys])); error.updatedAt = now
        }
        try context.save()
    }

    static func remove(id: String, records: [StoredRecord], context: ModelContext) throws {
        if let exam = records.first(where: { $0.collection == "exams" && $0.recordID == id }) { context.delete(exam) }
        for error in records where error.collection == "errors" {
            var object = error.jsonObject ?? [:]
            guard object["sourceExamId"] as? String == id else { continue }
            object.removeValue(forKey: "sourceExamId"); error.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])); error.updatedAt = .now
        }
        try context.save()
    }
}
