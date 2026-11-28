import SwiftData
import UIKit
import XCTest
@testable import KaogongReviewNative

@MainActor
final class LibraryErrorEditAndNoteTests: XCTestCase {
    func testErrorSaveHandsOffOnlyTheCommittedVersion() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoredRecord.self, configurations: configuration)
        let context = container.mainContext
        let initialPayload = try JSONSerialization.data(withJSONObject: [
            "id": "edit-handoff",
            "title": "原题干",
            "reviewSource": "real",
            "subject": "判断推理",
            "module": "类比推理"
        ])
        let record = StoredRecord(collection: "errors", recordID: "edit-handoff", payload: initialPayload)
        context.insert(record)
        try context.save()

        let cache = LibraryErrorDetailWarmCache.committedEdit
        cache.reset()
        defer { cache.reset() }
        var draft = LibraryRecordDraft(kind: .errors, scope: LibraryScope(), record: record)
        draft.title = "新题干"
        let savedID = try await LibraryRecordRepository.save(kind: .errors, draft: draft, records: [record], context: context)

        let readContext = ModelContext(container)
        let reloaded = try XCTUnwrap(try readContext.fetch(FetchDescriptor<StoredRecord>()).first { $0.recordID == savedID })
        let prepared = try XCTUnwrap(cache.prepared(for: reloaded))
        XCTAssertEqual(prepared.key, LibraryDetailPayloadKey(record: reloaded))
        XCTAssertEqual(prepared.object["title"] as? String, "新题干")
        XCTAssertNotNil(prepared.object["updatedAt"])
        XCTAssertNil(prepared.object["createdAt"])
        XCTAssertNil(LibraryRecordSnapshot(record: reloaded).errorEntryDate)
        let nextPayload = try JSONSerialization.data(withJSONObject: ["title": "其他窗口修改"])
        reloaded.replacePayload(nextPayload)
        XCTAssertNil(cache.prepared(for: reloaded))

        do {
            _ = try await LibraryRecordRepository.save(kind: .errors, draft: draft, records: [record], context: context)
            XCTFail("The original editor draft must not overwrite a newer record.")
        } catch LibraryRecordSaveError.recordChanged(_) {
            XCTAssertEqual(record.jsonObject?["title"] as? String, "新题干")
        }
    }

    func testErrorCardReadsOriginalCreationDateFromTheRecordOrLegacyPayload() throws {
        let payloadDate = Date(timeIntervalSince1970: 1_700_000_000.25)
        let storedDate = payloadDate.addingTimeInterval(-60)
        let updatedDate = payloadDate.addingTimeInterval(500)
        let payload = try JSONSerialization.data(withJSONObject: [
            "createdAt": "2023-11-14T22:13:20.250Z",
            "updatedAt": updatedDate.timeIntervalSince1970
        ])
        let record = StoredRecord(
            collection: "errors", recordID: "entry-date", payload: payload,
            createdAt: storedDate, updatedAt: updatedDate
        )

        XCTAssertEqual(LibraryRecordSnapshot(record: record).errorEntryDate, storedDate)
        record.createdAt = nil
        XCTAssertEqual(LibraryRecordSnapshot(record: record).errorEntryDate, payloadDate)
    }

    func testDataAnalysisOpensOneScopeForEveryStoredModule() throws {
        let subject = "资料分析"
        let scope = LibraryScope(subject: subject, module: "综合题")
        XCTAssertNil(scope.module)
        XCTAssertEqual(scope.title, subject)
        for (index, module) in ["单题", "综合题", "文字材料", nil].enumerated() {
            var object: [String: Any] = ["subject": subject, "title": "题目", "images": ["legacy-image"]]
            object["module"] = module
            let record = StoredRecord(
                collection: "errors", recordID: "analysis-\(index)",
                payload: try JSONSerialization.data(withJSONObject: object),
                subject: index == 3 ? nil : subject, module: module
            )
            XCTAssertTrue(scope.contains(record))
            XCTAssertNil(record.moduleDisplayTitle)
            XCTAssertEqual(
                SubjectModuleTitle.errorDetailTitle(
                    recordModule: module, payloadModule: module, questionBankModule: nil, subject: subject
                ),
                subject
            )
            let snapshot = LibraryRecordSnapshot(record: record, includeImages: true)
            XCTAssertTrue(snapshot.usesSingleCardImagePreview)
            XCTAssertTrue(snapshot.usesDataAnalysisMaterialLayout)
        }
        let type = LibraryErrorType(id: "old-composite", name: "作答策略", module: "综合题")
        XCTAssertTrue(LibraryErrorTypeSubject.dataAnalysis.accepts(type, in: ""))
        XCTAssertTrue(LibraryErrorTypeSubject.dataAnalysis.accepts(type, in: "单题"))
    }

    func testDataAnalysisSavePreservesLegacyModuleButOmitsItForNewQuestions() async throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoredRecord.self, configurations: configuration)
        let context = container.mainContext
        let scope = LibraryScope(subject: "资料分析")
        let payload = try JSONSerialization.data(withJSONObject: [
            "subject": "资料分析", "module": "单题", "title": "原题干", "reviewSource": "real"
        ])
        let original = StoredRecord(
            collection: "errors", recordID: "legacy-analysis", payload: payload,
            subject: "资料分析", module: "综合题"
        )
        context.insert(original)
        try context.save()

        var edited = LibraryRecordDraft(kind: .errors, scope: scope, record: original)
        edited.title = "新题干"
        _ = try await LibraryRecordRepository.save(kind: .errors, draft: edited, records: [original], context: context)
        XCTAssertEqual(original.module, "综合题")
        XCTAssertEqual(original.jsonObject?["module"] as? String, "单题")
        XCTAssertEqual(original.jsonObject?["title"] as? String, "新题干")

        var fresh = LibraryRecordDraft(kind: .errors, scope: scope)
        XCTAssertTrue(fresh.module.isEmpty)
        fresh.title = "另一题"
        fresh.module = "综合题" // A draft saved before the groups were removed.
        let newID = try await LibraryRecordRepository.save(kind: .errors, draft: fresh, records: [original], context: context)
        let created = try XCTUnwrap(context.fetch(FetchDescriptor<StoredRecord>()).first { $0.recordID == newID })
        XCTAssertNil(created.module)
        XCTAssertNil(created.jsonObject?["module"])
        XCTAssertTrue(scope.contains(created))
    }

    func testQuoteRemovesGrayFillAndPreservesColoredHighlight() {
        let text = NSMutableAttributedString(string: "引用高亮")
        text.addAttribute(.backgroundColor, value: UIColor.lightGray, range: NSRange(location: 0, length: 2))
        text.addAttribute(.backgroundColor, value: UIColor.systemYellow, range: NSRange(location: 2, length: 2))
        let rendered = NativeRichTextDisplayRenderer.applyingNoteFormatting(
            to: NativeRichTextDisplayRenderResult(attributedText: text, usedSafeFallback: false),
            sourceHTML: "<blockquote>引用高亮</blockquote>"
        ).attributedText
        XCTAssertNil(rendered.attribute(.backgroundColor, at: 0, effectiveRange: nil))
        XCTAssertEqual(rendered.attribute(.backgroundColor, at: 2, effectiveRange: nil) as? UIColor, .systemYellow)
        let paragraph = rendered.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertGreaterThanOrEqual(paragraph?.headIndent ?? 0, 14)
    }
}
