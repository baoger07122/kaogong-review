import Foundation
import SwiftData

enum WordReviewRepositoryError: LocalizedError {
    case missingPlan(String)
    case invalidWord(String)

    var errorDescription: String? {
        switch self {
        case let .missingPlan(id): "找不到复习计划：\(id)"
        case let .invalidWord(id): "词语条目不存在或内容不完整：\(id)"
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

    @discardableResult
    static func enrollPreparedCandidates(
        _ candidates: [WordReviewEnrollmentCandidate],
        wordRecords: [StoredRecord],
        in context: ModelContext,
        now: Date = .now,
        calendar: Calendar = .current
    ) throws -> Int {
        guard !candidates.isEmpty else { return 0 }
        let candidatesByID = Dictionary(candidates.map { ($0.wordRecordID, $0) }, uniquingKeysWith: { first, _ in first })
        let wordsByID = Dictionary(
            wordRecords.filter { $0.collection == "words" && candidatesByID[$0.recordID] != nil }
                .map { ($0.recordID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !wordsByID.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "word_review_plans" }
        )
        let plansByID = Dictionary(
            try context.fetch(descriptor).map { ($0.recordID, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var updates: [(StoredRecord, WordReviewPlan)] = []
        var inserts: [StoredRecord] = []
        for (wordRecordID, wordRecord) in wordsByID {
            guard let candidate = candidatesByID[wordRecordID] else { continue }
            let addedAt = wordRecord.createdAt ?? candidate.addedAt
            if let planRecord = plansByID[wordRecordID] {
                if let existingPlan = WordReviewPlan.decode(from: planRecord),
                   existingPlan.wordRecordID == wordRecordID {
                    guard let repaired = WordReviewEnrollmentPolicy.backfilledPlan(
                        existingPlan,
                        addedAt: addedAt,
                        now: now,
                        calendar: calendar
                    ) else { continue }
                    updates.append((planRecord, repaired))
                } else {
                    updates.append((planRecord, WordReviewEnrollmentPolicy.makePlan(
                        wordRecordID: wordRecordID,
                        addedAt: addedAt,
                        now: now,
                        calendar: calendar
                    )))
                }
            } else {
                let plan = WordReviewEnrollmentPolicy.makePlan(
                    wordRecordID: wordRecordID,
                    addedAt: addedAt,
                    now: now,
                    calendar: calendar
                )
                inserts.append(StoredRecord(
                    collection: "word_review_plans",
                    recordID: wordRecordID,
                    payload: try JSONEncoder().encode(plan),
                    subject: wordRecord.subject,
                    module: wordRecord.module,
                    createdAt: addedAt,
                    updatedAt: now
                ))
            }
        }
        guard !updates.isEmpty || !inserts.isEmpty else { return 0 }

        let encodedUpdates = try updates.map { record, plan in
            (record, plan, try JSONEncoder().encode(plan))
        }
        try context.transaction {
            for (record, plan, payload) in encodedUpdates {
                record.replacePayload(payload)
                record.updatedAt = plan.updatedAt
            }
            for record in inserts { context.insert(record) }
        }
        return inserts.count
    }

    @discardableResult
    static func enrollWithinTransaction(_ wordRecords: [StoredRecord], in context: ModelContext, now: Date = .now) throws -> Int {
        let candidates = wordRecords.filter { record in
            guard record.collection == "words",
                  let object = record.jsonObject,
                  WordReviewEnrollmentPolicy.isValidCategory(object["category"] as? String ?? object["type"] as? String ?? "")
            else { return false }
            return WordReviewWordGroup(record: record) != nil
        }
        guard !candidates.isEmpty else { return 0 }

        let descriptor = FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == "word_review_plans" }
        )
        var plansByID: [String: StoredRecord] = [:]
        for planRecord in try context.fetch(descriptor) { plansByID[planRecord.recordID] = planRecord }

        var insertedCount = 0
        for wordRecord in candidates {
            let addedAt = wordRecord.createdAt ?? payloadCreatedAt(wordRecord) ?? now
            if let existingRecord = plansByID[wordRecord.recordID],
               let existingPlan = WordReviewPlan.decode(from: existingRecord) {
                guard let repaired = WordReviewEnrollmentPolicy.backfilledPlan(
                    existingPlan,
                    addedAt: addedAt,
                    now: now
                ) else { continue }
                existingRecord.replacePayload(try JSONEncoder().encode(repaired))
                existingRecord.updatedAt = repaired.updatedAt
                continue
            }

            let plan = WordReviewEnrollmentPolicy.makePlan(
                wordRecordID: wordRecord.recordID,
                addedAt: addedAt,
                now: now
            )
            let planRecord = StoredRecord(
                collection: "word_review_plans",
                recordID: wordRecord.recordID,
                payload: try JSONEncoder().encode(plan),
                subject: wordRecord.subject,
                module: wordRecord.module,
                createdAt: addedAt,
                updatedAt: now
            )
            context.insert(planRecord)
            plansByID[wordRecord.recordID] = planRecord
            insertedCount += 1
        }
        return insertedCount
    }

    private static func payloadCreatedAt(_ record: StoredRecord) -> Date? {
        guard let value = record.jsonObject?["createdAt"] as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
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
