import Foundation
import SwiftData
import XCTest
@testable import KaogongReviewNative

@MainActor
final class QuestionBankAnalysisAdapterTests: XCTestCase {
    func testTypeMappingUsesExistingSpecializedLibraryBranchesAndPreservesUnknownLabels() {
        let cases: [(String, String, String?, String, String)] = [
            ("行测", "逻辑填空", "言语理解", "言语理解", "逻辑填空"),
            ("行测", "逻辑判断", "判断推理", "判断推理", "逻辑判断"),
            ("行测", "类比推理", "判断推理", "判断推理", "类比推理"),
            ("行测", "增长率", "资料分析", "资料分析", "增长率"),
            ("行测", "数学运算", "数量关系", "数量关系", "数学运算"),
            ("行测", "图形推理", "判断推理", "判断推理", "图形推理"),
            ("常识判断", "法律", "常识判断", "常识判断", "法律")
        ]

        for (rawSubject, type, moduleTitle, expectedSubject, expectedModule) in cases {
            XCTAssertEqual(
                QuestionBankLibraryTypeMapping.resolve(
                    subject: rawSubject,
                    type: type,
                    moduleTitle: moduleTitle
                ),
                QuestionBankLibraryTypeMapping(subject: expectedSubject, module: expectedModule)
            )
        }

        XCTAssertEqual(
            QuestionBankLibraryTypeMapping.resolve(
                subject: "未识别科目",
                type: "自定义题型",
                moduleTitle: "原始模块"
            ),
            QuestionBankLibraryTypeMapping(subject: "未识别科目", module: "原始模块")
        )
    }

    func testSourceRowsStripRecallEditionAndPDFWithoutShowingAuditMetadata() {
        let sources = [QuestionBankSourcePaper(
            id: "source-1",
            originalFileName: "2025年省考真题-网友回忆版.PDF",
            originalFileSHA256: "secret-hash"
        )]
        let entries = [QuestionBankProvenance(
            sourcePaperID: "source-1",
            sourceQuestionNumber: 17,
            originalPage: "4",
            evidence: "内部审计信息"
        )]

        XCTAssertEqual(QuestionBankSourceDisplay.rows(entries: entries, sourcePapers: sources), ["2025年省考真题·第17题"])
    }

    func testQuestionAnalysisWritesBackToQuestionPayloadAndOnlySyncsExplicitLinkedError() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let questionRecord = try makeQuestionRecord()
        let error = try makeLinkedError()
        let word = StoredRecord(collection: "words", recordID: "word-1", payload: Data("{}".utf8))
        context.insert(questionRecord)
        context.insert(error)
        context.insert(word)
        try context.save()
        let originalQuestionID = questionRecord.stableID
        let originalErrorCount = try context.fetch(FetchDescriptor<StoredRecord>()).count

        var analysis = QuestionBankQuestionAnalysisFields()
        analysis.errorCause = "辨析词义"
        analysis.pitfall = "忽略语境"
        analysis.graphRule = "旋转规律"
        analysis.recognition = "先看对称"
        analysis.note = "复盘后记"
        analysis.knowledgePoints = ["语境辨析"]
        analysis.weaknessTags = ["近义词"]
        analysis.linkedWordIDs = ["word-1"]
        analysis.linkedErrorRecordIDs = ["error-1"]
        let mapping = QuestionBankLibraryTypeMapping(subject: "言语理解", module: "逻辑填空")

        try QuestionBankRepository.updateQuestionAnalysis(
            record: questionRecord,
            paperID: "paper-1",
            questionID: "question-1",
            stem: "更新后的题干\n保留换行",
            optionTexts: ["option-a": "更新后的 A", "option-b": "更新后的 B"],
            answerOptionID: "option-a",
            annotations: QuestionBankQuestionAnnotations(
                isDifficult: true,
                needsReview: true,
                knowledgePoints: analysis.knowledgePoints,
                weaknessTags: analysis.weaknessTags
            ),
            analysis: analysis,
            typeMapping: mapping,
            sourceRows: ["2025年省考真题·第17题"],
            storedRecords: [error, word],
            context: context
        )

        let updated = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))
        XCTAssertEqual(questionRecord.stableID, originalQuestionID)
        XCTAssertEqual(updated.id, "question-1")
        XCTAssertEqual(updated.stem, "更新后的题干\n保留换行")
        XCTAssertEqual(updated.answer, "option-a")
        XCTAssertEqual(updated.options.map(\.id), ["option-a", "option-b"])
        XCTAssertEqual(updated.options.map(\.text), ["更新后的 A", "更新后的 B"])
        XCTAssertEqual(updated.options.map(\.imageAssetID), ["option-image-a", "option-image-b"])
        XCTAssertEqual(updated.isDifficult, true)
        XCTAssertEqual(updated.needsReview, true)
        XCTAssertEqual(updated.errorCause, "辨析词义")
        XCTAssertEqual(updated.graphRule, "旋转规律")
        XCTAssertEqual(updated.recognition, "先看对称")
        XCTAssertEqual(updated.note, "复盘后记")
        XCTAssertTrue(questionRecord.searchText.contains("旋转规律"))
        XCTAssertTrue(questionRecord.searchText.contains("先看对称"))
        XCTAssertEqual(updated.linkedErrorRecordIDs, ["error-1"])
        let questionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: questionRecord.payload) as? [String: Any])
        XCTAssertEqual(questionObject["vendorQuestionField"] as? String, "preserve-me")
        let options = try XCTUnwrap(questionObject["options"] as? [[String: Any]])
        XCTAssertEqual(options.first?["vendorOptionField"] as? String, "also-preserve")
        XCTAssertNil(questionObject["reviewCount"], "True-question editing must not add wrong-review state")

        let linkedError = try XCTUnwrap(error.jsonObject)
        XCTAssertEqual(linkedError["question"] as? String, updated.stem)
        XCTAssertEqual(linkedError["correctOption"] as? String, "A")
        XCTAssertEqual(linkedError["questionBankPaperID"] as? String, "paper-1")
        XCTAssertEqual(linkedError["questionBankQuestionID"] as? String, "question-1")
        XCTAssertEqual(linkedError["status"] as? String, "未掌握")
        XCTAssertEqual(linkedError["reviewCount"] as? Int, 6)
        let savedStoredRecords = try context.fetch(FetchDescriptor<StoredRecord>())
        XCTAssertEqual(savedStoredRecords.count, originalErrorCount)
        XCTAssertEqual(savedStoredRecords.filter { $0.collection == "errors" }.count, 1)
        XCTAssertEqual(savedStoredRecords.filter { $0.collection == "words" }.count, 1)
    }

    func testMissingExplicitErrorLinkDoesNotCreateStoredRecordOrChangeQuestion() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let questionRecord = try makeQuestionRecord()
        context.insert(questionRecord)
        try context.save()
        let originalPayload = questionRecord.payload
        var analysis = QuestionBankQuestionAnalysisFields()
        analysis.linkedErrorRecordIDs = ["not-created"]

        XCTAssertThrowsError(try QuestionBankRepository.updateQuestionAnalysis(
            record: questionRecord,
            paperID: "paper-1",
            questionID: "question-1",
            stem: "不应写入",
            optionTexts: [:],
            answerOptionID: "option-b",
            annotations: QuestionBankQuestionAnnotations(),
            analysis: analysis,
            typeMapping: QuestionBankLibraryTypeMapping(subject: "言语理解", module: "逻辑填空"),
            sourceRows: [],
            storedRecords: [],
            context: context
        ))

        XCTAssertEqual(questionRecord.payload, originalPayload)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredRecord>()).isEmpty)
    }

    func testEditingAnExplicitlyLinkedErrorWritesBackToTheTrueQuestionInOneSave() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let questionRecord = try makeQuestionRecord()
        let error = try makeLinkedError()
        context.insert(questionRecord)
        context.insert(error)
        try context.save()

        var draft = LibraryRecordDraft(
            kind: .errors,
            scope: LibraryScope(subject: "言语理解", module: "逻辑填空"),
            record: error
        )
        draft.title = "从错题编辑器更新题干"
        draft.options[0] = "错题编辑器更新的选项"
        draft.correctOption = "A"
        draft.errorCause = "语境判断"
        draft.status = "已掌握"
        try LibraryRecordRepository.save(kind: .errors, draft: draft, records: [error], context: context)

        let updated = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))
        XCTAssertEqual(updated.stem, "从错题编辑器更新题干")
        XCTAssertEqual(updated.options[0].text, "错题编辑器更新的选项")
        XCTAssertEqual(updated.answer, "option-a")
        XCTAssertEqual(updated.errorCause, "语境判断")
        XCTAssertEqual(updated.linkedErrorRecordIDs, ["error-1"])
        XCTAssertEqual(questionRecord.stableID, "question-1")
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).count, 1)
        XCTAssertEqual(error.jsonObject?["reviewCount"] as? Int, 6)
    }

    func testStaleQuestionBankLinkDoesNotBlockEditingOrDeletingWrongQuestion() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let error = StoredRecord(
            collection: "errors",
            recordID: "orphan-error",
            payload: try JSONSerialization.data(withJSONObject: [
                "id": "orphan-error",
                "question": "旧题干",
                "options": ["A", "B", "C", "D"],
                "correctOption": "A",
                "questionBankPaperID": "deleted-paper",
                "questionBankQuestionID": "deleted-question"
            ], options: [.sortedKeys]),
            subject: "言语理解",
            module: "逻辑填空"
        )
        context.insert(error)
        try context.save()

        var draft = LibraryRecordDraft(
            kind: .errors,
            scope: LibraryScope(subject: "言语理解", module: "逻辑填空"),
            record: error
        )
        draft.title = "仍可编辑的错题"
        try LibraryRecordRepository.save(kind: .errors, draft: draft, records: [error], context: context)
        XCTAssertEqual(error.jsonObject?["question"] as? String, "仍可编辑的错题")

        try LibraryRecordRepository.remove(kind: .errors, id: error.recordID, records: [error], context: context)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredRecord>()).isEmpty)
    }

    private func makeMemoryContainer() throws -> ModelContainer {
        let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    private func makeQuestionRecord() throws -> QuestionBankRecord {
        let payloadObject: [String: Any] = [
            "id": "question-1",
            "paperID": "paper-1",
            "moduleID": "module-1",
            "number": 17,
            "subject": "行测",
            "type": "逻辑填空",
            "materialID": "",
            "stem": "原始题干",
            "stemImageAssetID": "stem-image",
            "options": [
                ["id": "option-a", "text": "原 A", "imageAssetID": "option-image-a", "vendorOptionField": "also-preserve"],
                ["id": "option-b", "text": "原 B", "imageAssetID": "option-image-b"]
            ],
            "answer": "option-b",
            "explanation": "原解析",
            "originalPage": "4",
            "vendorQuestionField": "preserve-me"
        ]
        return QuestionBankRecord(
            compoundID: "paper-1::question::question-1",
            paperID: "paper-1",
            kind: QuestionBankRepository.questionKind,
            stableID: "question-1",
            moduleID: "module-1",
            questionNumber: 17,
            searchText: "原始题干 原 A 原 B",
            payload: try JSONSerialization.data(withJSONObject: payloadObject, options: [.sortedKeys])
        )
    }

    private func makeLinkedError() throws -> StoredRecord {
        let object: [String: Any] = [
            "id": "error-1",
            "question": "原始题干",
            "options": ["原 A", "原 B"],
            "correctOption": "B",
            "status": "未掌握",
            "reviewCount": 6,
            "questionBankPaperID": "paper-1",
            "questionBankQuestionID": "question-1"
        ]
        return StoredRecord(
            collection: "errors",
            recordID: "error-1",
            payload: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            subject: "言语理解",
            module: "逻辑填空"
        )
    }
}
