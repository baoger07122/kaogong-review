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
