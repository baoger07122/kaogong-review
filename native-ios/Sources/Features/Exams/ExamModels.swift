import Foundation
import Observation
import SwiftData

struct ExamSubjectScore: Identifiable, Equatable {
    var subject: String
    var score: String
    var totalScore: String
    var id: String { subject }
}

@Observable
final class ExamDraft {
    var original: [String: Any] = [:]
    var id = ""
    var examType: LibraryReviewSource = .real
    var name = ""
    var examDate = Date()
    var rawReport = ""
    var moduleResults: [ExamModuleResult] = []
    var score = ""
    var maximumScore = ""
    // Kept for legacy payload preservation; the new editor never derives score from these values.
    var subjectScores: [ExamSubjectScore] = []
    var totalAccuracy = ""
    var totalTime = ""
    var targetScore = ""
    var reviewNote = ""
    var linkedErrorIDs: Set<String> = []

    init(record: StoredRecord? = nil) {
        original = record?.jsonObject ?? [:]
        id = record?.recordID ?? ""
        examType = record == nil ? .real : (LibraryReviewSource.explicitValue(in: original) ?? .pending)
        name = original["name"] as? String ?? ""
        if let value = original["examDate"] as? String { examDate = Self.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .now }
        rawReport = original["rawReport"] as? String ?? ""
        if let values = original["moduleResults"] as? [[String: Any]] {
            moduleResults = values.compactMap { value in
                guard let subject = value["subject"] as? String else { return nil }
                return ExamModuleResult(
                    id: value["id"] as? String ?? UUID().uuidString,
                    subject: subject,
                    parentSubject: value["parentSubject"] as? String,
                    totalQuestions: Self.stringValue(value["totalQuestions"]),
                    correctCount: Self.stringValue(value["correctCount"]),
                    reportedAccuracy: Self.stringValue(value["reportedAccuracy"]),
                    timeSeconds: Self.stringValue(value["timeSeconds"])
                )
            }
        }
        if let values = original["subjectScores"] as? [[String: Any]] {
            subjectScores = values.compactMap {
                guard let subject = $0["subject"] as? String else { return nil }
                return ExamSubjectScore(subject: subject, score: Self.stringValue($0["score"]), totalScore: Self.stringValue($0["totalScore"]))
            }
        }
        totalAccuracy = Self.stringValue(original["totalAccuracy"])
        totalTime = Self.stringValue(original["totalTime"])
        targetScore = Self.stringValue(original["targetScore"])
        score = Self.stringValue(original["score"])
        maximumScore = Self.stringValue(original["maximumScore"])
        reviewNote = original["reviewNote"] as? String ?? ""
        linkedErrorIDs = Set(original["linkedErrorIds"] as? [String] ?? [])
    }

    var metrics: ExamDerivedMetrics { ExamReportParser.metrics(for: moduleResults) }

    static let dayFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone.current
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String ?? ""
    }
}

enum ExamRepository {
    static func save(
        _ draft: ExamDraft,
        derivedMetrics: ExamDerivedMetrics? = nil,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> String {
        let now = Date()
        let id = draft.id.isEmpty ? "exam_\(Int(now.timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))" : draft.id
        let existing = records.first { $0.collection == "exams" && $0.recordID == id }
        var object = draft.original
        let uniqueErrorIDs = Array(draft.linkedErrorIDs).sorted()
        let metrics = derivedMetrics ?? draft.metrics
        object["id"] = id
        object["name"] = draft.name
        object["examType"] = draft.examType.rawValue
        object["examDate"] = ExamDraft.dayFormatter.string(from: draft.examDate)
        object["rawReport"] = draft.rawReport
        object["moduleResults"] = draft.moduleResults.map(\.payloadObject)
        object["linkedErrorIds"] = uniqueErrorIDs
        object["updatedAt"] = ISO8601DateFormatter().string(from: now)
        if let score = Double(draft.score), score.isFinite { object["score"] = score } else { object.removeValue(forKey: "score") }
        if let maximumScore = Double(draft.maximumScore), maximumScore.isFinite, maximumScore > 0 { object["maximumScore"] = maximumScore } else { object.removeValue(forKey: "maximumScore") }
        if let total = metrics.totalQuestions { object["totalQuestions"] = total } else { object.removeValue(forKey: "totalQuestions") }
        if let correct = metrics.correctCount { object["correctCount"] = correct } else { object.removeValue(forKey: "correctCount") }
        if let wrong = metrics.wrongCount { object["wrongCount"] = wrong } else { object.removeValue(forKey: "wrongCount") }
        if let accuracy = metrics.accuracyPercent { object["weightedAccuracy"] = accuracy } else { object.removeValue(forKey: "weightedAccuracy") }
        if let seconds = metrics.totalTimeSeconds { object["totalTimeSeconds"] = seconds } else { object.removeValue(forKey: "totalTimeSeconds") }
        object["reviewNote"] = draft.reviewNote
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        try context.transaction {
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = now
            } else {
                context.insert(StoredRecord(collection: "exams", recordID: id, payload: payload, createdAt: now, updatedAt: now))
            }
            let errorRecords = records.filter { $0.collection == "errors" }
            for error in errorRecords {
                var errorObject = error.jsonObject ?? [:]
                let previousExamID = errorObject["sourceExamId"] as? String ?? ""
                let shouldLink = draft.linkedErrorIDs.contains(error.recordID)
                let isLinkedHere = previousExamID == id
                guard shouldLink || isLinkedHere else { continue }
                if shouldLink {
                    if !previousExamID.isEmpty, previousExamID != id,
                       let previousExam = records.first(where: { $0.collection == "exams" && $0.recordID == previousExamID }) {
                        var previousObject = previousExam.jsonObject ?? [:]
                        let priorIDs = Set(previousObject["linkedErrorIds"] as? [String] ?? [])
                        previousObject["linkedErrorIds"] = Array(priorIDs.subtracting(Set([error.recordID]))).sorted()
                        previousObject["updatedAt"] = ISO8601DateFormatter().string(from: now)
                        previousExam.replacePayload(try JSONSerialization.data(withJSONObject: previousObject, options: [.sortedKeys]))
                        previousExam.updatedAt = now
                    }
                    errorObject["sourceExamId"] = id
                    errorObject["reviewSource"] = draft.examType.rawValue
                } else {
                    errorObject.removeValue(forKey: "sourceExamId")
                }
                errorObject["updatedAt"] = ISO8601DateFormatter().string(from: now)
                error.replacePayload(try JSONSerialization.data(withJSONObject: errorObject, options: [.sortedKeys]))
                error.updatedAt = now
            }
            if existing != nil, draft.examType != .mock,
               LibraryMockExamMemory.selectedID(records: records) == id {
                try LibraryMockExamMemory.remember("", records: records, context: context)
            }
        }
        return id
    }

    static func remove(id: String, records: [StoredRecord], context: ModelContext) throws {
        try context.transaction {
            if let exam = records.first(where: { $0.collection == "exams" && $0.recordID == id }) { context.delete(exam) }
            let now = ISO8601DateFormatter().string(from: .now)
            for error in records where error.collection == "errors" {
                var object = error.jsonObject ?? [:]
                guard object["sourceExamId"] as? String == id else { continue }
                object.removeValue(forKey: "sourceExamId")
                object["updatedAt"] = now
                error.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                error.updatedAt = .now
            }
            if LibraryMockExamMemory.selectedID(records: records) == id {
                try LibraryMockExamMemory.remember("", records: records, context: context)
            }
        }
    }
}
