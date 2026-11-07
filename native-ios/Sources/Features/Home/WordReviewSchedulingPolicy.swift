import Foundation

enum WordReviewPlanStatus: String, Codable, CaseIterable, Hashable {
    case waitingToLearn
    case training
    case verification
    case stable

    var title: String {
        switch self {
        case .waitingToLearn: "待学习"
        case .training: "待训练"
        case .verification: "待验证"
        case .stable: "已稳定"
        }
    }
}

enum WordReviewFeedback: String, Codable, CaseIterable, Hashable {
    case unknown
    case fuzzy
    case mastered

    var title: String {
        switch self {
        case .unknown: "不会"
        case .fuzzy: "模糊"
        case .mastered: "掌握"
        }
    }
}

enum WordReviewAttemptType: String, Codable, Hashable {
    case due
    case early
    var title: String { self == .due ? "到期复习" : "提前复习" }
}

struct WordReviewPlan: Codable, Equatable, Identifiable {
    var wordRecordID: String
    var status: WordReviewPlanStatus
    var isPaused: Bool
    var verificationRound: Int
    var isContextValidationPending: Bool
    var firstPassedOn: Date?
    var nextDueDate: Date?
    var createdAt: Date
    var updatedAt: Date

    var id: String { wordRecordID }
}

enum WordReviewSchedulingPolicy {
    static func finishPreparation(_ plan: WordReviewPlan, on date: Date, calendar: Calendar = .current) -> WordReviewPlan {
        var updated = plan
        updated.status = .training
        updated.verificationRound = 0
        updated.isContextValidationPending = false
        updated.firstPassedOn = nil
        updated.nextDueDate = calendar.startOfDay(for: date)
        updated.updatedAt = date
        return updated
    }

    static func applying(
        _ feedback: WordReviewFeedback,
        to plan: WordReviewPlan,
        attemptType: WordReviewAttemptType,
        on date: Date,
        calendar: Calendar = .current
    ) -> WordReviewPlan {
        var updated = plan
        updated.updatedAt = date
        guard attemptType == .due else { return updated }

        let today = calendar.startOfDay(for: date)
        switch feedback {
        case .unknown:
            updated.status = .training
            updated.verificationRound = 0
            updated.isContextValidationPending = false
            updated.firstPassedOn = nil
            updated.nextDueDate = adding(days: 1, to: today, calendar: calendar)
        case .fuzzy:
            updated.nextDueDate = adding(days: 1, to: today, calendar: calendar)
        case .mastered:
            if plan.status == .training || plan.verificationRound == 0 {
                updated.status = .verification
                updated.verificationRound = 1
                updated.firstPassedOn = today
                updated.isContextValidationPending = false
                updated.nextDueDate = adding(days: 1, to: today, calendar: calendar)
            } else if plan.status == .verification, (1...4).contains(plan.verificationRound) {
                let intervals = [2, 4, 7, 16]
                updated.verificationRound += 1
                updated.nextDueDate = adding(days: intervals[plan.verificationRound - 2], to: today, calendar: calendar)
            } else if plan.status == .verification, plan.verificationRound == 5 {
                updated.status = .verification
                updated.isContextValidationPending = true
                updated.nextDueDate = nil
            } else {
                updated.nextDueDate = nil
            }
        }
        return updated
    }

    static func isDue(_ date: Date?, on today: Date, calendar: Calendar = .current) -> Bool {
        guard let date else { return false }
        return calendar.startOfDay(for: date) <= calendar.startOfDay(for: today)
    }

    private static func adding(days: Int, to date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: calendar.startOfDay(for: date))
            .map { calendar.startOfDay(for: $0) }
    }
}
