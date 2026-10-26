import Foundation
import XCTest
@testable import KaogongReviewNative

@MainActor
final class LibraryDraftStoreTests: XCTestCase {
    func testWordComparisonTermsPersistByCategoryAndScopeWithoutTitle() throws {
        let scope = LibraryScope(subject: "言语理解", module: "逻辑填空")
        let category = WordCategory.idiomComparison.rawValue
        LibraryDraftStore.clear(kind: .words, scope: scope, category: category)
        defer { LibraryDraftStore.clear(kind: .words, scope: scope, category: category) }

        var draft = LibraryRecordDraft(kind: .words, scope: scope)
        draft.type = category
        draft.title = ""
        var first = WordComparisonTermDraft()
        first.name = "水到渠成"
        first.meaning = "条件成熟后自然成功"
        var second = WordComparisonTermDraft()
        second.name = "顺理成章"
        second.meaning = "事情发展合乎情理"
        draft.wordCompareTerms = [first, second]

        let snapshot = LibraryDraftSnapshot(draft)
        XCTAssertTrue(snapshot.hasUserContent)
        LibraryDraftStore.save(snapshot, kind: .words, scope: scope)

        let restored = try XCTUnwrap(
            LibraryDraftStore.load(kind: .words, scope: scope, category: category)
        )
        XCTAssertEqual(restored.title, "")
        XCTAssertEqual(restored.wordCompareTerms?.map(\.name), ["水到渠成", "顺理成章"])
        XCTAssertEqual(restored.wordCompareTerms?.map(\.meaning), ["条件成熟后自然成功", "事情发展合乎情理"])
        XCTAssertNil(LibraryDraftStore.load(
            kind: .words,
            scope: scope,
            category: WordCategory.wordComparison.rawValue
        ))

        var emptyDraft = LibraryRecordDraft(kind: .words, scope: scope)
        emptyDraft.type = category
        var emptyTerm = WordComparisonTermDraft()
        emptyTerm.name = ""
        emptyTerm.meaning = ""
        emptyDraft.wordCompareTerms = [emptyTerm, WordComparisonTermDraft()]
        XCTAssertFalse(LibraryDraftSnapshot(emptyDraft).hasUserContent)
    }

    func testWordCardPreviewKeepsParagraphsBreaksAndActualNewlines() {
        let preview = LibraryWordCardPreviewText.render("<p>第一行</p><p>第二<br>行\n用户换行</p>")
        XCTAssertEqual(preview, "第一行\n第二\n行\n用户换行")
    }
}
