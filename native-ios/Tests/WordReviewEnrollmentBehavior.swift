import Foundation

@main
struct WordReviewEnrollmentBehavior {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let addedAt = calendar.date(from: DateComponents(year: 2026, month: 11, day: 8, hour: 16))!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 9))!

        expect(WordReviewEnrollmentPolicy.validCategoryRawValues == Set([
            "idiom-def", "idiom-compare", "word-def", "word-compare"
        ]), "the four definition and comparison categories are eligible")
        for category in WordReviewEnrollmentPolicy.validCategoryRawValues {
            expect(WordReviewEnrollmentPolicy.isValidCategory(category), "every supported category is accepted")
        }
        expect(!WordReviewEnrollmentPolicy.isValidCategory("unknown"), "unknown categories do not enter review")

        let newPlan = WordReviewEnrollmentPolicy.makePlan(
            wordRecordID: "word-1",
            addedAt: addedAt,
            now: now,
            calendar: calendar
        )
        expect(newPlan.status == .waitingToLearn, "a new word begins in the waiting state")
        expect(newPlan.createdAt == addedAt, "the plan keeps the word's original add date")
        expect(newPlan.nextDueDate == calendar.startOfDay(for: addedAt), "the plan is due on the local add date")

        var legacy = newPlan
        legacy.isPaused = true
        legacy.verificationRound = 3
        legacy.nextDueDate = nil
        legacy.updatedAt = addedAt
        let repaired = WordReviewEnrollmentPolicy.backfilledPlan(legacy, addedAt: addedAt, now: now, calendar: calendar)
        expect(repaired?.nextDueDate == calendar.startOfDay(for: addedAt), "a waiting plan without a date is repaired from the word date")
        expect(repaired?.isPaused == true && repaired?.verificationRound == 3, "backfill preserves pause and review progress")
        expect(WordReviewEnrollmentPolicy.backfilledPlan(repaired!, addedAt: now, now: now, calendar: calendar) == nil,
            "backfill is idempotent and does not move an existing due date")

        var progressing = legacy
        progressing.status = .training
        expect(WordReviewEnrollmentPolicy.backfilledPlan(progressing, addedAt: addedAt, now: now, calendar: calendar) == nil,
            "non-waiting progress is never rewritten during backfill")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
