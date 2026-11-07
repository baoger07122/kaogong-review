import Foundation

@main
struct WordReviewDomainBehavior {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let day7 = date(2026, 11, 7, 19, calendar: calendar)
        let plan = WordReviewPlan(
            wordRecordID: "word-group-1",
            status: .training,
            isPaused: false,
            verificationRound: 0,
            isContextValidationPending: false,
            firstPassedOn: nil,
            nextDueDate: day7,
            createdAt: day7,
            updatedAt: day7
        )

        let firstPass = WordReviewSchedulingPolicy.applying(.mastered, to: plan, attemptType: .due, on: day7, calendar: calendar)
        expect(firstPass.status == .verification && firstPass.verificationRound == 1, "the first pass must enter verification round 1")
        expect(day(firstPass.nextDueDate, calendar) == date(2026, 11, 8, 0, calendar: calendar), "the first verification must be due on the next local day")

        let roundOneDate = date(2026, 11, 8, 22, calendar: calendar)
        let roundTwo = WordReviewSchedulingPolicy.applying(.mastered, to: firstPass, attemptType: .due, on: roundOneDate, calendar: calendar)
        expect(roundTwo.verificationRound == 2, "a pass in round 1 must schedule round 2")
        expect(day(roundTwo.nextDueDate, calendar) == date(2026, 11, 10, 0, calendar: calendar), "round 2 must use two local calendar days")

        let fuzzy = WordReviewSchedulingPolicy.applying(.fuzzy, to: roundTwo, attemptType: .due, on: date(2026, 11, 10, 23, calendar: calendar), calendar: calendar)
        expect(fuzzy.verificationRound == 2, "fuzzy feedback must keep the verification round")
        expect(day(fuzzy.nextDueDate, calendar) == date(2026, 11, 11, 0, calendar: calendar), "fuzzy feedback must retry the next local day")

        let reset = WordReviewSchedulingPolicy.applying(.unknown, to: fuzzy, attemptType: .due, on: date(2026, 11, 11, 12, calendar: calendar), calendar: calendar)
        expect(reset.status == .training && reset.verificationRound == 0, "unknown feedback must restart training")
        expect(day(reset.nextDueDate, calendar) == date(2026, 11, 12, 0, calendar: calendar), "unknown feedback must return tomorrow")

        var completed = WordReviewSchedulingPolicy.applying(.mastered, to: reset, attemptType: .due, on: date(2026, 11, 12, 8, calendar: calendar), calendar: calendar)
        let expectedIntervals = [2, 4, 7, 16]
        var completionDate = date(2026, 11, 13, 20, calendar: calendar)
        for (index, interval) in expectedIntervals.enumerated() {
            let passed = WordReviewSchedulingPolicy.applying(.mastered, to: completed, attemptType: .due, on: completionDate, calendar: calendar)
            expect(passed.verificationRound == index + 2, "verification rounds must advance in order")
            let expected = calendar.date(byAdding: .day, value: interval, to: calendar.startOfDay(for: completionDate))!
            expect(day(passed.nextDueDate, calendar) == calendar.startOfDay(for: expected), "pass intervals must be measured from completion day")
            completed = passed
            completionDate = passed.nextDueDate ?? completionDate
        }
        let contextPending = WordReviewSchedulingPolicy.applying(.mastered, to: completed, attemptType: .due, on: completionDate, calendar: calendar)
        expect(contextPending.status == .verification, "the fifth pass must not mark the group stable automatically")
        expect(contextPending.isContextValidationPending && contextPending.nextDueDate == nil, "the fifth pass must wait for context validation")

        let early = WordReviewSchedulingPolicy.applying(.unknown, to: roundTwo, attemptType: .early, on: date(2026, 11, 9, 10, calendar: calendar), calendar: calendar)
        expect(early.verificationRound == roundTwo.verificationRound && early.nextDueDate == roundTwo.nextDueDate, "early review must leave round and due date unchanged")

        let importedWords: Set<String> = ["word-group-1"]
        expect(LegacyWordReviewRestorePolicy.shouldPreserveLocalRecord(
            collection: "word_review_plans", includesCollection: false, wordRecordID: "word-group-1",
            importedWordIDs: importedWords, importedReviewRecordIDs: [], recordID: "word-group-1"
        ), "a legacy backup may inherit a matching local plan")
        expect(!LegacyWordReviewRestorePolicy.shouldPreserveLocalRecord(
            collection: "word_review_plans", includesCollection: true, wordRecordID: "word-group-1",
            importedWordIDs: importedWords, importedReviewRecordIDs: [], recordID: "word-group-1"
        ), "an explicitly present empty plan array must clear plans")
        expect(!LegacyWordReviewRestorePolicy.shouldPreserveLocalRecord(
            collection: "word_review_history", includesCollection: false, wordRecordID: "deleted-word",
            importedWordIDs: importedWords, importedReviewRecordIDs: [], recordID: "history-1"
        ), "local review records must not attach to missing imported word groups")
        expect(!LegacyWordReviewRestorePolicy.shouldPreserveLocalRecord(
            collection: "word_review_history", includesCollection: false, wordRecordID: "word-group-1",
            importedWordIDs: importedWords, importedReviewRecordIDs: ["word_review_history:history-1"], recordID: "history-1"
        ), "a review record present in the backup must not be duplicated")
    }

    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
    }

    private static func day(_ date: Date?, _ calendar: Calendar) -> Date? {
        date.map { calendar.startOfDay(for: $0) }
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
