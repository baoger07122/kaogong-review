import Foundation
import SwiftData
import XCTest
import UIKit
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
            context: context
        ))

        XCTAssertEqual(questionRecord.payload, originalPayload)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StoredRecord>()).isEmpty)
    }

    func testMultiBlankQuestionEditRejectsConcatenatedOptionUntilItsBoundaryIsExplicit() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let original = try makeQuestionRecord()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original.payload) as? [String: Any])
        object["stem"] = "在（ ）和（ ）中选择"
        let initialPayload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        original.replacePayload(initialPayload)
        let module = QuestionBankRecord(
            compoundID: "paper-1::module::module-1",
            paperID: "paper-1",
            kind: QuestionBankRepository.moduleKind,
            stableID: "module-1",
            title: "逻辑填空",
            payload: Data("{}".utf8)
        )
        context.insert(original)
        context.insert(module)
        try context.save()

        XCTAssertThrowsError(try QuestionBankRepository.updateQuestionText(
            paperID: "paper-1",
            questionID: "question-1",
            stem: "在（ ）和（ ）中选择",
            optionTexts: ["option-a": "水到渠成融汇贯通", "option-b": "鱼贯而入一气呵成"],
            records: [module, original],
            context: context
        )) { error in
            guard let failure = error as? QuestionBankQuestionTextEditFailure,
                  case .invalidMultiBlankOption = failure else {
                return XCTFail("Expected explicit multi-blank boundary validation, got \(error)")
            }
        }
        XCTAssertEqual(original.payload, initialPayload, "Rejected glued text must leave the stored payload untouched")

        try QuestionBankRepository.updateQuestionText(
            paperID: "paper-1",
            questionID: "question-1",
            stem: "在（ ）和（ ）中选择",
            optionTexts: ["option-a": "水到渠成    融汇贯通", "option-b": "鱼贯而入    一气呵成"],
            records: [module, original],
            context: context
        )
        let updated = try XCTUnwrap(original.decoded(QuestionBankQuestion.self))
        XCTAssertEqual(updated.options[0].text, "水到渠成    融汇贯通")
        XCTAssertEqual(QuestionBankMultiBlankOptionText.parse(updated.options[0].text, blankCount: 2)?.groups,
                       ["水到渠成", "融汇贯通"])
    }

    func testSavingNoteDoesNotRejectOrRewriteLegacyConcatenatedMultiBlankOptions() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let questionRecord = try makeQuestionRecord()
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: questionRecord.payload) as? [String: Any])
        object["stem"] = "在（ ）与（ ）之间选择"
        var options = try XCTUnwrap(object["options"] as? [[String: Any]])
        options[0]["text"] = "水到渠成融汇贯通"
        options[1]["text"] = "鱼贯而入一气呵成"
        object["options"] = options
        questionRecord.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        context.insert(questionRecord)
        try context.save()

        var analysis = QuestionBankQuestionAnalysisFields()
        analysis.note = "<p>普通中文笔记<b>保留格式</b></p>"
        let before = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))

        try QuestionBankRepository.updateQuestionAnalysis(
            record: questionRecord,
            paperID: "paper-1",
            questionID: "question-1",
            stem: before.stem,
            optionTexts: Dictionary(before.options.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first }),
            answerOptionID: before.answer,
            annotations: QuestionBankQuestionAnnotations(question: before),
            analysis: analysis,
            typeMapping: QuestionBankLibraryTypeMapping(subject: "言语理解", module: "逻辑填空"),
            sourceRows: [],
            context: context
        )

        let after = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))
        XCTAssertEqual(after.stem, before.stem)
        XCTAssertEqual(after.options, before.options)
        XCTAssertEqual(after.note, analysis.note)
    }

    func testRichQuestionNoteSurvivesClosingAndReopeningTheSwiftDataStore() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("QuestionBankRichNoteRestart-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("QuestionBank.store")

        do {
            let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
            let configuration = ModelConfiguration(
                "QuestionBankRichNoteRestart",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let questionRecord = try makeQuestionRecord()
            context.insert(questionRecord)
            try context.save()

            let question = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))
            var analysis = QuestionBankQuestionAnalysisFields()
            analysis.note = "<p>普通中文<b>富文本笔记</b>\n第二行</p>"
            try QuestionBankRepository.updateQuestionAnalysis(
                record: questionRecord,
                paperID: "paper-1",
                questionID: "question-1",
                stem: question.stem,
                optionTexts: Dictionary(question.options.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first }),
                answerOptionID: question.answer,
                annotations: QuestionBankQuestionAnnotations(question: question),
                analysis: analysis,
                typeMapping: QuestionBankLibraryTypeMapping(subject: "言语理解", module: "逻辑填空"),
                sourceRows: [],
                context: context
            )
        }

        let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
        let configuration = ModelConfiguration(
            "QuestionBankRichNoteRestart",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let persisted = try XCTUnwrap(
            reopened.mainContext.fetch(FetchDescriptor<QuestionBankRecord>()).first
        )
        XCTAssertEqual(
            persisted.decoded(QuestionBankQuestion.self)?.note,
            "<p>普通中文<b>富文本笔记</b>\n第二行</p>"
        )
    }

    func testRichTextDisplayRendersFormattedTextAndSafelyFallsBackForOversizedMarkup() throws {
        let formatted = NativeRichTextDisplayRenderer.render("<p>短中文<b>加粗内容</b></p>")
        XCTAssertFalse(formatted.usedSafeFallback)
        XCTAssertTrue(formatted.attributedText.string.contains("短中文"))
        XCTAssertTrue(formatted.attributedText.string.contains("加粗内容"))
        let boldRange = try XCTUnwrap(formatted.attributedText.string.range(of: "加粗内容"))
        let nsRange = NSRange(boldRange, in: formatted.attributedText.string)
        let font = try XCTUnwrap(formatted.attributedText.attribute(.font, at: nsRange.location, effectiveRange: nil) as? UIFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.traitBold))

        let oversized = "<p>原始笔记保留</p>" + String(repeating: "长文本", count: 90_000)
        let fallback = NativeRichTextDisplayRenderer.render(oversized)
        XCTAssertTrue(fallback.usedSafeFallback)
        XCTAssertTrue(fallback.attributedText.string.contains("原始笔记保留"))
        XCTAssertTrue(fallback.attributedText.string.contains("原内容仍保留"))
        XCTAssertTrue(oversized.contains("<p>原始笔记保留</p>"), "Display fallback must not mutate the saved payload")
    }

    func testReferenceAccuracyWritesAndClearsWithoutAcceptingOutOfRangeValues() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let question = try makeQuestionRecord()
        context.insert(question)
        try context.save()

        let initialRevision = question.contentRevision
        try QuestionBankRepository.updateReferenceAccuracy(
            record: question,
            accuracy: 42.5,
            context: context
        )
        XCTAssertEqual(question.decoded(QuestionBankQuestion.self)?.accuracy, 42.5)
        XCTAssertEqual(question.contentRevision, initialRevision + 1)
        let savedPayload = question.payload

        XCTAssertThrowsError(try QuestionBankRepository.updateReferenceAccuracy(
            record: question,
            accuracy: 100.1,
            context: context
        ))
        XCTAssertEqual(question.payload, savedPayload)

        try QuestionBankRepository.updateReferenceAccuracy(record: question, accuracy: nil, context: context)
        XCTAssertNil(question.decoded(QuestionBankQuestion.self)?.accuracy)
        XCTAssertNil((try JSONSerialization.jsonObject(with: question.payload) as? [String: Any])?["accuracy"])
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

    func testQuestionBankErrorRecordIdentityIsStableAndSeparatesCategories() {
        let wrongID = QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-1", category: .wrong
        )
        XCTAssertEqual(wrongID, QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-1", category: .wrong
        ))
        XCTAssertNotEqual(wrongID, QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-1", category: .uncertain
        ))
        XCTAssertNotEqual(wrongID, QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-1", category: .cannotSolve
        ))
        XCTAssertEqual(QuestionBankErrorBookCategory.cannotSolve.rawValue, "不会做")
        XCTAssertNotEqual(wrongID, QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-2", questionID: "question-1", category: .wrong
        ))
    }

    func testOneTapErrorBookAddPreservesQuestionAssetsAndIsIdempotent() throws {
        let container = try makeMemoryContainer()
        let context = container.mainContext
        let questionRecord = try makeQuestionRecord()
        var questionObject = try XCTUnwrap(JSONSerialization.jsonObject(with: questionRecord.payload) as? [String: Any])
        questionObject["materialID"] = "material-1"
        questionObject["note"] = "<p>原有<b>复盘笔记</b></p>"
        questionObject["knowledgePoints"] = ["语境辨析"]
        questionRecord.replacePayload(try JSONSerialization.data(withJSONObject: questionObject, options: [.sortedKeys]))
        let module = QuestionBankRecord(
            compoundID: "paper-1::module::module-1", paperID: "paper-1",
            kind: QuestionBankRepository.moduleKind, stableID: "module-1",
            title: "逻辑填空", payload: Data("{}".utf8)
        )
        let material = QuestionBankRecord(
            compoundID: "paper-1::material::material-1", paperID: "paper-1",
            kind: QuestionBankRepository.materialKind, stableID: "material-1",
            moduleID: "module-1", title: "共用材料",
            payload: try JSONEncoder().encode(QuestionBankMaterial(
                id: "material-1", paperID: "paper-1", moduleID: "module-1",
                type: "材料", text: "材料正文", imageAssetID: "material-image",
                applicableQuestions: "17", originalPage: "3"
            ))
        )
        let paper = QuestionBankRecord(
            compoundID: "paper-1::paper::paper-1", paperID: "paper-1",
            kind: QuestionBankRepository.paperKind, stableID: "paper-1",
            title: "2025 国考", payload: try JSONEncoder().encode(QuestionBankPaper(
                id: "paper-1", title: "2025 国考", year: 2025,
                examType: "国考", volume: "", source: "fixture", importVersion: "1"
            ))
        )
        let assets = ["stem-image", "option-image-a", "option-image-b", "material-image"].map { id in
            QuestionBankRecord(
                compoundID: "paper-1::asset::\(id)", paperID: "paper-1",
                kind: QuestionBankRepository.assetKind, stableID: id,
                payload: Data("{}".utf8), assetRelativePath: "paper-1/assets/\(id).png"
            )
        }
        for record in [questionRecord, module, material, paper] { context.insert(record) }
        for record in assets { context.insert(record) }
        try context.save()

        let bankRecords = try context.fetch(FetchDescriptor<QuestionBankRecord>())
        let analysis = try XCTUnwrap(QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: "paper-1", questionID: "question-1", selectedOption: "A", records: bankRecords
        ))
        XCTAssertEqual(analysis.material?.text, "材料正文")
        XCTAssertEqual(analysis.assetsByID["material-image"]?.assetRelativePath, "paper-1/assets/material-image.png")

        let result = try QuestionBankErrorBookRepository.add(
            analysis: analysis,
            question: analysis.currentQuestion,
            category: .wrong,
            candidateRecordIDs: [],
            context: context
        )
        let expectedID = QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-1", category: .wrong
        )
        XCTAssertEqual(result, .added(recordID: expectedID))

        let savedError = try XCTUnwrap(context.fetch(FetchDescriptor<StoredRecord>()).first {
            $0.collection == "errors" && $0.recordID == expectedID
        })
        let saved = try XCTUnwrap(savedError.jsonObject)
        XCTAssertEqual(saved["type"] as? String, "错题")
        XCTAssertEqual(saved["status"] as? String, "未掌握")
        XCTAssertEqual(saved["questionBankPaperID"] as? String, "paper-1")
        XCTAssertEqual(saved["questionBankQuestionID"] as? String, "question-1")
        XCTAssertEqual(saved["question"] as? String, "原始题干")
        XCTAssertEqual(saved["options"] as? [String], ["原 A", "原 B"])
        XCTAssertEqual(saved["correctOption"] as? String, "B")
        XCTAssertEqual(saved["userOption"] as? String, "A")
        XCTAssertEqual(saved["images"] as? [String], ["stem-image"])
        XCTAssertEqual(saved["optionImages"] as? [String], ["option-image-a", "option-image-b"])
        XCTAssertEqual(saved["materialID"] as? String, "material-1")
        XCTAssertEqual(saved["note"] as? String, "<p>原有<b>复盘笔记</b></p>")
        XCTAssertEqual(saved["knowledgePoints"] as? [String], ["语境辨析"])
        XCTAssertEqual(saved["reviewCount"] as? Int, 0)

        let updatedQuestion = try XCTUnwrap(questionRecord.decoded(QuestionBankQuestion.self))
        XCTAssertEqual(updatedQuestion.linkedErrorRecordIDs, [expectedID])
        XCTAssertEqual(updatedQuestion.note, "<p>原有<b>复盘笔记</b></p>")
        XCTAssertEqual(updatedQuestion.options.map(\.imageAssetID), ["option-image-a", "option-image-b"])
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).filter { $0.collection == "errors" }.count, 1)

        XCTAssertEqual(
            try QuestionBankErrorBookRepository.add(
                analysis: analysis,
                question: analysis.currentQuestion,
                category: .wrong,
                candidateRecordIDs: [expectedID],
                context: context
            ),
            .alreadyAdded(recordID: expectedID)
        )
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).filter { $0.collection == "errors" }.count, 1)

        var secondQuestionObject = questionObject
        secondQuestionObject["id"] = "question-2"
        secondQuestionObject["number"] = 18
        let secondQuestionRecord = QuestionBankRecord(
            compoundID: "paper-1::question::question-2", paperID: "paper-1",
            kind: QuestionBankRepository.questionKind, stableID: "question-2",
            moduleID: "module-1", questionNumber: 18,
            payload: try JSONSerialization.data(withJSONObject: secondQuestionObject, options: [.sortedKeys])
        )
        context.insert(secondQuestionRecord)
        try context.save()
        let correctAnalysis = try XCTUnwrap(QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: "paper-1", questionID: "question-2", selectedOption: "B",
            records: try context.fetch(FetchDescriptor<QuestionBankRecord>())
        ))
        let uncertainResult = try QuestionBankErrorBookRepository.add(
            analysis: correctAnalysis,
            question: correctAnalysis.currentQuestion,
            category: .uncertain,
            candidateRecordIDs: [],
            context: context
        )
        let uncertainID = QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-2", category: .uncertain
        )
        XCTAssertEqual(uncertainResult, .added(recordID: uncertainID))
        let uncertainRecord = try XCTUnwrap(context.fetch(FetchDescriptor<StoredRecord>()).first {
            $0.collection == "errors" && $0.recordID == uncertainID
        })
        XCTAssertEqual(uncertainRecord.jsonObject?["type"] as? String, "不确定题")
        XCTAssertEqual(uncertainRecord.jsonObject?["userOption"] as? String, "B")
        XCTAssertEqual(try context.fetch(FetchDescriptor<StoredRecord>()).filter { $0.collection == "errors" }.count, 2)

        var thirdQuestionObject = questionObject
        thirdQuestionObject["id"] = "question-3"
        thirdQuestionObject["number"] = 19
        let thirdQuestionRecord = QuestionBankRecord(
            compoundID: "paper-1::question::question-3", paperID: "paper-1",
            kind: QuestionBankRepository.questionKind, stableID: "question-3",
            moduleID: "module-1", questionNumber: 19,
            payload: try JSONSerialization.data(withJSONObject: thirdQuestionObject, options: [.sortedKeys])
        )
        context.insert(thirdQuestionRecord)
        try context.save()
        let cannotSolveAnalysis = try XCTUnwrap(QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: "paper-1", questionID: "question-3", selectedOption: "",
            records: try context.fetch(FetchDescriptor<QuestionBankRecord>())
        ))
        let cannotSolveResult = try QuestionBankErrorBookRepository.add(
            analysis: cannotSolveAnalysis,
            question: cannotSolveAnalysis.currentQuestion,
            category: .cannotSolve,
            candidateRecordIDs: [],
            context: context
        )
        let cannotSolveID = QuestionBankErrorBookIdentity.recordID(
            paperID: "paper-1", questionID: "question-3", category: .cannotSolve
        )
        XCTAssertEqual(cannotSolveResult, .added(recordID: cannotSolveID))
        let cannotSolveRecord = try XCTUnwrap(context.fetch(FetchDescriptor<StoredRecord>()).first {
            $0.collection == "errors" && $0.recordID == cannotSolveID
        })
        XCTAssertEqual(cannotSolveRecord.jsonObject?["type"] as? String, "不会做")
        XCTAssertEqual(cannotSolveRecord.jsonObject?["userOption"] as? String, "")
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
