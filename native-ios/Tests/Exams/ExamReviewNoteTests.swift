import Foundation
import SwiftData
import XCTest
@testable import KaogongReviewNative

@MainActor
final class ExamReviewNoteTests: XCTestCase {
    func testLegacyNoteAndIndependentSavePreserveOtherPayloadFields() throws {
        let (context, record) = try savedExam()
        let original = ExamReviewNote(in: try XCTUnwrap(record.jsonObject))
        XCTAssertEqual(original.summary, "保留原来的富文本")
        XCTAssertEqual(original.nextAction, "")

        let note = ExamReviewNote(html: original.html, nextAction: "先做资料分析\n保留十分钟检查")
        try ExamRepository.saveReviewNote(note, replacing: original, in: record, context: context)

        let object = try XCTUnwrap(record.jsonObject)
        XCTAssertEqual(ExamReviewNote(in: object), note)
        XCTAssertEqual(note.summary, "先做资料分析")
        XCTAssertEqual(object["score"] as? Int, 65)
        XCTAssertEqual(object["linkedErrorIds"] as? [String], ["error-1"])
        XCTAssertEqual(object["legacyExtra"] as? String, "保留")
    }

    func testStaleDraftCannotReplaceNewerNotesAndScoreEditRetainsThem() throws {
        let (context, record) = try savedExam()
        let scoreDraft = ExamDraft(record: record)
        let original = ExamReviewNote(in: try XCTUnwrap(record.jsonObject))
        let latest = ExamReviewNote(html: "<p>新备注</p>", nextAction: "重新安排限时")
        try ExamRepository.saveReviewNote(latest, replacing: original, in: record, context: context)

        let stale = ExamReviewNote(html: "", nextAction: "旧草稿")
        XCTAssertThrowsError(try ExamRepository.saveReviewNote(stale, replacing: original, in: record, context: context))

        scoreDraft.score = "70"
        _ = try ExamRepository.save(scoreDraft, records: [record], context: context)
        let object = try XCTUnwrap(record.jsonObject)
        XCTAssertEqual(ExamReviewNote(in: object), latest)
        XCTAssertEqual(object["score"] as? Int, 70)
    }

    private func savedExam() throws -> (ModelContext, StoredRecord) {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoredRecord.self, configurations: configuration)
        let context = container.mainContext
        let payload = try JSONSerialization.data(withJSONObject: [
            "id": "exam-1",
            "name": "测试套卷",
            "examType": LibraryReviewSource.real.rawValue,
            "score": 65,
            "reviewNote": "<p><strong>保留原来的富文本</strong></p>",
            "linkedErrorIds": ["error-1"],
            "legacyExtra": "保留"
        ] as [String: Any])
        let record = StoredRecord(collection: "exams", recordID: "exam-1", payload: payload)
        context.insert(record)
        try context.save()
        return (context, record)
    }
}
