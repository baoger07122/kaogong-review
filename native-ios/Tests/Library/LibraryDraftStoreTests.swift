import Foundation
import XCTest
@testable import KaogongReviewNative

@MainActor
final class LibraryDraftStoreTests: XCTestCase {
    func testWordDraftsAreNotRestoredOrWrittenAndLegacyDataIsKept() async throws {
        let scope = LibraryScope(subject: "言语理解", module: "逻辑填空")
        let category = WordCategory.idiomComparison.rawValue
        let key = "native.library.draft.words.real.言语理解.逻辑填空.category.\(category)"
        let defaults = UserDefaults.standard
        let previousValue = defaults.object(forKey: key)
        let legacyData = Data("legacy-word-draft".utf8)
        defaults.set(legacyData, forKey: key)
        defer {
            if let previousValue { defaults.set(previousValue, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }

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
        await LibraryDraftStore.flush(snapshot, kind: .words, scope: scope)
        XCTAssertNil(LibraryDraftStore.load(kind: .words, scope: scope, category: category))
        XCTAssertEqual(defaults.data(forKey: key), legacyData)
        await LibraryDraftStore.clearAndWait(kind: .words, scope: scope, category: category)
        XCTAssertEqual(defaults.data(forKey: key), legacyData)
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
