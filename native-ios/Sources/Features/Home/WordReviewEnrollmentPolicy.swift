import Foundation

enum WordReviewEnrollmentPolicy {
    static let validCategoryRawValues: Set<String> = [
        "idiom-def", "idiom-compare", "word-def", "word-compare"
    ]

    static func isValidCategory(_ rawValue: String) -> Bool {
        validCategoryRawValues.contains(rawValue)
    }

    static func dueDate(for wordAddedAt: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: wordAddedAt)
    }

    static func makePlan(wordRecordID: String, addedAt: Date, now: Date, calendar: Calendar = .current) -> WordReviewPlan {
        WordReviewPlan(
            wordRecordID: wordRecordID,
            status: .waitingToLearn,
            isPaused: false,
            verificationRound: 0,
            isContextValidationPending: false,
            firstPassedOn: nil,
            nextDueDate: dueDate(for: addedAt, calendar: calendar),
            createdAt: addedAt,
            updatedAt: now
        )
    }

    static func backfilledPlan(
        _ plan: WordReviewPlan,
        addedAt: Date,
        now: Date,
        calendar: Calendar = .current
    ) -> WordReviewPlan? {
        guard plan.status == .waitingToLearn, plan.nextDueDate == nil else { return nil }
        var updated = plan
        updated.nextDueDate = dueDate(for: addedAt, calendar: calendar)
        updated.updatedAt = now
        return updated
    }
}
