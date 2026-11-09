import Foundation
import SwiftData

enum WordReviewRepositoryError: LocalizedError {
    case missingPlan(String)
    case invalidWord(String)

    var errorDescription: String? {
        switch self {
        case let .missingPlan(id): "找不到复习计划：\(id)"
        case let .invalidWord(id): "词语条目已不存在或不是辨析组：\(id)"
        }
    }
}

@MainActor
enum WordReviewRepository {
    static func plans(from records: [StoredRecord]) -> [WordReviewPlan] {
        records.compactMap(WordReviewPlan.decode(from:))
    }

    static func history(from records: [StoredRecord]) -> [WordReviewHistory] {
        records.compactMap(WordReviewHistory.decode(from:))
            .sorted { lhs, rhs in
                if lhs.reviewedAt != rhs.reviewedAt { return lhs.reviewedAt > rhs.reviewedAt }
                return lhs.id > rhs.id
            }
    }

    @discardableResult
    static func enroll(_ wordRecords: [StoredRecord], in context: ModelContext, now: Date = .now) throws -> Int {
        let candidates = wordRecords.compactMap { record -> (StoredRecord, WordReviewWordGroup)? in
            guard let group = WordReviewWordGroup(record: record) else { return nil }
            return (record, group)
        }
        guard !candidates.isEmpty else { return 0 }

        var insertedCount = 0
        try context.transaction {
            let descriptor = FetchDescriptor<StoredRecord>(
                predicate: #Predicate { $0.collection == "word_review_plans" }
            )
            var existingIDs = Set(try context.fetch(descriptor).map(\.recordID))
            for (record, _) in candidates where existingIDs.insert(record.recordID).inserted {
                let plan = WordReviewPlan(
                    wordRecordID: record.recordID,
                    status: .waitingToLearn,
                    isPaused: false,
                    verificationRound: 0,
                    isContextValidationPending: false,
                    firstPassedOn: nil,
                    nextDueDate: nil,
                    createdAt: now,
                    updatedAt: now
                )
                context.insert(StoredRecord(
                    collection: "word_review_plans",
                    recordID: record.recordID,
                    payload: try JSONEncoder().encode(plan),
                    subject: record.subject,
                    module: record.module,
                    createdAt: now,
                    updatedAt: now
                ))
                insertedCount += 1
            }
        }
        return insertedCount
    }

    static func setPaused(_ isPaused: Bool, wordRecordID: String, in context: ModelContext, now: Date = .now) throws {
        try updatePlan(wordRecordID: wordRecordID, in: context) { plan in
            plan.isPaused = isPaused
            plan.updatedAt = now
        }
    }

    @discardableResult
    static func submit(
        wordRecordID: String,
        title: String,
        categoryTitle: String,
        feedback: WordReviewFeedback,
        attemptType: WordReviewAttemptType,
        submissionID: String,
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> WordReviewHistory {
        var result: WordReviewHistory?
        try context.transaction {
            let historyPredicate = #Predicate<StoredRecord> {
                $0.collection == "word_review_history" && $0.recordID == submissionID
            }
            if let existing = try context.fetch(FetchDescriptor<StoredRecord>(predicate: historyPredicate)).first,
               let decoded = WordReviewHistory.decode(from: existing) {
                result = decoded
                return
            }

            guard let planRecord = try fetchPlanRecord(wordRecordID: wordRecordID, in: context),
                  var plan = WordReviewPlan.decode(from: planRecord) else {
                throw WordReviewRepositoryError.missingPlan(wordRecordID)
            }
            let previousDueDate = plan.nextDueDate
            let reviewRound = plan.verificationRound
            plan = WordReviewSchedulingPolicy.applying(
                feedback,
                to: plan,
                attemptType: attemptType,
                on: now,
                calendar: calendar
            )
            planRecord.replacePayload(try JSONEncoder().encode(plan))
            planRecord.updatedAt = now

            let history = WordReviewHistory(
                id: submissionID,
                wordRecordID: wordRecordID,
                title: title,
                categoryTitle: categoryTitle,
                attemptType: attemptType,
                feedback: feedback,
                reviewedAt: now,
                reviewRound: reviewRound,
                previousDueDate: previousDueDate,
                nextDueDate: plan.nextDueDate,
                isContextValidationPending: plan.isContextValidationPending
            )
            context.insert(StoredRecord(
                collection: "word_review_history",
                recordID: submissionID,
                payload: try JSONEncoder().encode(history),
                subject: "言语理解",
                module: "逻辑填空",
                createdAt: now,
                updatedAt: now
            ))
            result = history
        }
        guard let result else { throw WordReviewRepositoryError.missingPlan(wordRecordID) }
        return result
    }

    private static func updatePlan(
        wordRecordID: String,
        in context: ModelContext,
        mutation: (inout WordReviewPlan) -> Void
    ) throws {
        try context.transaction {
            guard let record = try fetchPlanRecord(wordRecordID: wordRecordID, in: context),
                  var plan = WordReviewPlan.decode(from: record) else {
                throw WordReviewRepositoryError.missingPlan(wordRecordID)
            }
            mutation(&plan)
            record.replacePayload(try JSONEncoder().encode(plan))
            record.updatedAt = plan.updatedAt
        }
    }

    private static func fetchPlanRecord(wordRecordID: String, in context: ModelContext) throws -> StoredRecord? {
        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate {
                $0.collection == "word_review_plans" && $0.recordID == wordRecordID
            }
        )
        return try context.fetch(descriptor).first
    }
}
