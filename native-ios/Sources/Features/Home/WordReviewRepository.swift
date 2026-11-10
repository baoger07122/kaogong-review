import Foundation
import SwiftData

enum WordReviewRepositoryError: LocalizedError {
    case missingPlan(String)
    case invalidWord(String)

    var errorDescription: String? {
        switch self {
        case let .missingPlan(id): "找不到复习计划：\(id)"
        case let .invalidWord(id): "词语条目已不存在或内容不完整：\(id)"
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
        var insertedCount = 0
        try context.transaction {
            insertedCount = try enrollWithinTransaction(wordRecords, in: context, now: now)
        }
        return insertedCount
    }

    /// Adds or repairs a word's review record inside the caller's transaction.
    /// New words become due on their local calendar creation date; existing
    /// review progress and scheduled dates are preserved.
    @discardableResult
    static func enrollWithinTransaction(
        _ wordRecords: [StoredRecord],
        in context: ModelContext,
        now: Date = .now
    ) throws -> Int {
        let candidates = wordRecords.compactMap { record -> StoredRecord? in
            WordReviewWordGroup(record: record) == nil ? nil : record
        }
        guard !candidates.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "word_review_plans" }
        )
        var plansByWordID = Dictionary(uniqueKeysWithValues: try context.fetch(descriptor).map { ($0.recordID, $0) })
        var insertedCount = 0

        for record in candidates {
            let addedAt = wordAddedAt(record, fallback: now)
            let dueDate = Calendar.current.startOfDay(for: addedAt)
            if let planRecord = plansByWordID[record.recordID] {
                guard var plan = WordReviewPlan.decode(from: planRecord) else { continue }
                guard plan.status == .waitingToLearn, plan.nextDueDate == nil else { continue }
                plan.nextDueDate = dueDate
                plan.updatedAt = now
                planRecord.replacePayload(try JSONEncoder().encode(plan))
                planRecord.updatedAt = now
                continue
            }

            let plan = WordReviewPlan(
                wordRecordID: record.recordID,
                status: .waitingToLearn,
                isPaused: false,
                verificationRound: 0,
                isContextValidationPending: false,
                firstPassedOn: nil,
                nextDueDate: dueDate,
                createdAt: addedAt,
                updatedAt: now
            )
            let planRecord = StoredRecord(
                collection: "word_review_plans",
                recordID: record.recordID,
                payload: try JSONEncoder().encode(plan),
                subject: record.subject,
                module: record.module,
                createdAt: addedAt,
                updatedAt: now
            )
            context.insert(planRecord)
            plansByWordID[record.recordID] = planRecord
            insertedCount += 1
        }
        return insertedCount
    }

    private static func wordAddedAt(_ record: StoredRecord, fallback: Date) -> Date {
        if let createdAt = record.createdAt { return createdAt }
        guard let value = record.jsonObject?["createdAt"] as? String else { return fallback }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        return ISO8601DateFormatter().date(from: value) ?? fallback
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
