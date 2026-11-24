import Foundation
import SwiftData
import XCTest
@testable import KaogongReviewNative

@MainActor
final class ShenlunPaperRepositoryTests: XCTestCase {
    func testSavingPaperKeepsIndependentQuestionsAndSharedMaterials() throws {
        let context = try memoryContext()
        let practice = ShenlunWorkspacePractice(
            id: "paper", name: "测试套卷", kind: .paper,
            questionIDs: ["first", "second"], materialIDs: ["shared", "second-only"], materialDecisionMade: true
        )
        let first = ShenlunWorkspaceQuestion(
            id: "first", practiceID: practice.id, order: 0, title: "第一题",
            maximumWordCount: 200, materialIDs: ["shared"], materialDecisionMade: true
        )
        let second = ShenlunWorkspaceQuestion(
            id: "second", practiceID: practice.id, order: 1, type: .essay, title: "第二题",
            maximumWordCount: 800, materialIDs: ["shared", "second-only"], materialDecisionMade: true
        )
        let shared = ShenlunWorkspaceMaterial(
            id: "shared", practiceID: practice.id, title: "材料 1", order: 0, text: "共享段落"
        )
        let asset = ShenlunWorkspaceAsset(
            id: "asset", practiceID: practice.id, fileName: "image.jpg", mimeType: "image/jpeg", data: Data([1, 2, 3])
        )
        let secondOnly = ShenlunWorkspaceMaterial(
            id: "second-only", practiceID: practice.id, title: "材料 2", order: 1, kind: .image, assetID: asset.id
        )
        for _ in 0..<2 {
            try ShenlunWorkspaceRepository.saveNewPractice(
                practice, questions: [first, second], materials: [shared, secondOnly], assets: [asset], in: context
            )
        }
        XCTAssertEqual(try ShenlunWorkspaceRepository.practices(in: context).map(\.id), [practice.id])
        XCTAssertEqual(try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: context), [first, second])
        XCTAssertEqual(try ShenlunWorkspaceRepository.materials(practiceID: practice.id, in: context), [shared, secondOnly])
        XCTAssertEqual(try ShenlunWorkspaceRepository.asset(id: asset.id, in: context)?.data, asset.data)
    }

    func testEncodingFailureLeavesNoPartialPaper() throws {
        let context = try memoryContext()
        let practice = ShenlunWorkspacePractice(
            id: "paper", name: "测试套卷", kind: .paper, questionIDs: ["first", "second"], materialIDs: ["material"]
        )
        let first = ShenlunWorkspaceQuestion(id: "first", practiceID: practice.id, order: 0, title: "第一题")
        let invalid = ShenlunWorkspaceQuestion(
            id: "second", practiceID: practice.id, order: 1, title: "第二题", fullScore: .infinity
        )
        let material = ShenlunWorkspaceMaterial(
            id: "material", practiceID: practice.id, title: "材料 1", order: 0, text: "材料内容"
        )
        XCTAssertThrowsError(try ShenlunWorkspaceRepository.saveNewPractice(
            practice, questions: [first, invalid], materials: [material], assets: [], in: context
        ))
        XCTAssertNil(try ShenlunWorkspaceRepository.practice(id: practice.id, in: context))
        XCTAssertTrue(try ShenlunWorkspaceRepository.questions(practiceID: practice.id, in: context).isEmpty)
        XCTAssertTrue(try ShenlunWorkspaceRepository.materials(practiceID: practice.id, in: context).isEmpty)
    }

    func testLegacyAnswerStaysIndependentOfRetryAndBackfill() throws {
        let context = try memoryContext()
        let question = ShenlunWorkspaceQuestion(id: "q", practiceID: "paper", order: 0, fullScore: 20)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let legacy = ShenlunWorkspaceAnswer(
            practiceID: "paper", questionID: "q", answerText: "旧作答", isCompleted: true,
            completedAt: date, reviewState: .confirmed, confirmedScore: 12
        )
        context.insert(StoredRecord(
            collection: ShenlunWorkspaceRepository.answerCollection, recordID: question.id,
            payload: try JSONEncoder().encode(legacy), subject: "申论", createdAt: date, updatedAt: date
        ))
        try context.save()

        let migrated = try XCTUnwrap(ShenlunWorkspaceRepository.attemptHistories(practiceID: "paper", in: context)["q"])
        XCTAssertEqual(migrated.completed.map(\.attemptNumber), [1])
        XCTAssertEqual(migrated.latestScored?.confirmedScore, 12)

        var retry = ShenlunWorkspaceAnswer(practiceID: "paper", questionID: "q", answerText: "第二次草稿")
        retry.attemptID = "retry"
        let duringRetry = try ShenlunWorkspaceRepository.saveAttempt(retry, replacingRevision: nil, in: context)
        XCTAssertEqual(duringRetry.completed.count, 1)
        XCTAssertEqual(duringRetry.draft?.answerText, "第二次草稿")
        XCTAssertThrowsError(try ShenlunWorkspaceRepository.saveAttempt(retry, replacingRevision: nil, in: context))

        var backfill = ShenlunWorkspaceAnswer(practiceID: "paper", questionID: "q")
        backfill.attemptID = "backfill"
        backfill.complete(on: date.addingTimeInterval(-100), for: question)
        let afterBackfill = try ShenlunWorkspaceRepository.saveAttempt(backfill, replacingRevision: nil, in: context)
        XCTAssertEqual(afterBackfill.completed.map(\.id), ["q", "backfill"])
        XCTAssertEqual(afterBackfill.draft?.id, "retry")

        retry = try XCTUnwrap(afterBackfill.draft)
        retry.complete(on: date.addingTimeInterval(100), for: question)
        let afterRetry = try ShenlunWorkspaceRepository.saveAttempt(retry, replacingRevision: retry.revision, in: context)
        XCTAssertEqual(afterRetry.completed.map(\.attemptNumber), [3, 1, 2])
        XCTAssertEqual(afterRetry.completed.map(\.answerText), ["第二次草稿", "旧作答", ""])
        XCTAssertNil(afterRetry.draft)
        XCTAssertThrowsError(try ShenlunWorkspaceRepository.saveAttempt(retry, replacingRevision: retry.revision, in: context))

        let reloaded = try XCTUnwrap(ShenlunWorkspaceRepository.attemptHistories(in: context)["q"])
        XCTAssertEqual(reloaded, afterRetry)
        let records = try context.fetch(FetchDescriptor<StoredRecord>())
        let backup = try LegacyBackupImporter.parse(data: LegacyBackupExporter.makeData(records: records))
        XCTAssertEqual(backup.counts[ShenlunWorkspaceRepository.answerCollection], 1)
        let archived = try XCTUnwrap(backup.records.first { $0.collection == ShenlunWorkspaceRepository.attemptCollection })
        XCTAssertEqual(try JSONDecoder().decode(ShenlunWorkspaceAttemptHistory.self, from: archived.payload), afterRetry)
    }

    func testReviewDraftAndScoreClearingUseTheSameAttempt() throws {
        let context = try memoryContext()
        let question = ShenlunWorkspaceQuestion(id: "q", practiceID: "single", order: 0, fullScore: 20)
        var answer = ShenlunWorkspaceAnswer(practiceID: "single", questionID: "q", answerText: "作答")
        answer.attemptID = "first"
        answer.complete(on: .now, for: question)
        answer.confirmedScore = 16
        answer.reviewState = .confirmed
        var history = try ShenlunWorkspaceRepository.saveAttempt(answer, replacingRevision: nil, in: context)
        answer = try XCTUnwrap(history.completed.first)

        var draft = answer.savedReview
        draft.scoreText = "0"
        draft.note = "复盘心得"
        XCTAssertEqual(try draft.validatedScore(maximum: 20), 0)
        draft.scoreText = "20.01"
        XCTAssertThrowsError(try draft.validatedScore(maximum: 20))
        draft.scoreText = "10.001"
        XCTAssertThrowsError(try draft.validatedScore(maximum: nil))
        draft.scoreText = ""
        XCTAssertNil(try draft.validatedScore(maximum: 20))

        answer.reviewDraft = draft
        history = try ShenlunWorkspaceRepository.saveAttempt(answer, replacingRevision: answer.revision, in: context)
        answer = try XCTUnwrap(history.completed.first)
        XCTAssertEqual(answer.confirmedScore, 16)
        XCTAssertEqual(answer.reviewDraft?.note, "复盘心得")

        answer.confirmedScore = nil
        answer.reviewState = .notReviewed
        answer.reviewNote = draft.note
        answer.reviewDraft = nil
        _ = try ShenlunWorkspaceRepository.saveAttempt(answer, replacingRevision: answer.revision, in: context)
        let reloaded = try XCTUnwrap(ShenlunWorkspaceRepository.attemptHistories(practiceID: "single", in: context)["q"])
        XCTAssertEqual(reloaded.completed.count, 1)
        XCTAssertNil(reloaded.completed.first?.confirmedScore)
        XCTAssertNil(reloaded.completed.first?.reviewDraft)
        XCTAssertEqual(reloaded.completed.first?.reviewNote, "复盘心得")
    }

    private func memoryContext() throws -> ModelContext {
        let schema = Schema([StoredRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }
}
