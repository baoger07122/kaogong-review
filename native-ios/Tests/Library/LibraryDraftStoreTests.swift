import Foundation
import UIKit
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

    func testWordCardUsesDefinitionFromRichTextInsteadOfOpeningHeadings() throws {
        let meaning = "形容做事情粗疏、不够细致，处理问题笼统，缺乏深入分析。"
        let body = "<h2>一、词义理解</h2><p>大而化之</p><p><strong>词义：</strong>\(meaning)</p>"
            + "<h2>二、具体情境</h2><p>基层调查研究</p>"
        let payload = try JSONSerialization.data(withJSONObject: [
            "name": "大而化之",
            "category": WordCategory.idiomDefinition.rawValue,
            "meaning": body
        ])
        let record = StoredRecord(collection: "words", recordID: "definition", payload: payload)

        let snapshot = LibraryRecordSnapshot(record: record)
        XCTAssertEqual(snapshot.wordCardPreview, meaning)
        XCTAssertTrue(snapshot.searchableText.contains("基层调查研究"))
    }

    func testWordCardReadsLegacyContentAndSavedComparisonOutsideIndex() throws {
        let definition = try JSONSerialization.data(withJSONObject: [
            "name": "按部就班",
            "category": WordCategory.idiomDefinition.rawValue,
            "content": "成语积累｜按部就班\n一、词义理解\n按部就班\n依照一定的步骤、顺序进行。"
        ])
        let comparison = try JSONSerialization.data(withJSONObject: [
            "name": "循序渐进／按部就班",
            "category": WordCategory.idiomComparison.rawValue,
            "commonMeaning": "旧版共同语义",
            "comparisonDocument": "<h2>核心区别</h2><p>前者强调逐步深入，后者强调遵循既定步骤。</p>"
        ])
        let oldWord = StoredRecord(collection: "words", recordID: "legacy", payload: definition)
        let newComparison = StoredRecord(collection: "words", recordID: "comparison", payload: comparison)

        XCTAssertEqual(LibraryRecordSnapshot(record: oldWord).wordCardPreview, "依照一定的步骤、顺序进行。")
        XCTAssertEqual(LibraryRecordSnapshot(record: newComparison).wordCardPreview, "前者强调逐步深入，后者强调遵循既定步骤。")
    }

    func testWordCardSkipsEmptyHeadingsAndComparisonTableHeader() {
        let empty = LibraryWordCardPreviewText.render("<h2>一、词义理解</h2><p>按部就班</p><p>释义：</p>")
        let table = LibraryWordCardPreviewText.render("""
        <h2>词义区别</h2><table><tr><th>成语</th><th>词义</th><th>核心侧重</th></tr>
        <tr><td>按部就班</td><td>依照步骤进行</td><td>讲顺序</td></tr></table>
        """)

        XCTAssertEqual(LibraryWordCardPreviewText.cardSummary(empty, title: "按部就班", isComparison: false), "")
        XCTAssertEqual(
            LibraryWordCardPreviewText.cardSummary(table, title: "按部就班／循序渐进", isComparison: true),
            "按部就班 · 依照步骤进行 · 讲顺序"
        )
    }

    func testWordDetailSpacingPreservesFontsAndExistingLargerSpacing() throws {
        let body = "正文第一段\n"
        let heading = "二、具体情境"
        let bodyFont = UIFont.systemFont(ofSize: 16)
        let headingFont = UIFont.systemFont(ofSize: 18, weight: .semibold)
        let source = NSMutableAttributedString(string: body, attributes: [.font: bodyFont])
        let headingStyle = NSMutableParagraphStyle()
        headingStyle.paragraphSpacingBefore = 11
        source.append(NSAttributedString(string: heading, attributes: [
            .font: headingFont,
            .paragraphStyle: headingStyle,
            NativeRichTextPastePolicy.semanticHeadingParagraph: 2
        ]))

        let displayed = NativeRichTextDisplayRenderer.applyingWordDetailSpacing(to: source, usedSafeFallback: false)
        let headingOffset = body.utf16.count
        let displayedBodyStyle = try XCTUnwrap(displayed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        let displayedHeadingStyle = try XCTUnwrap(displayed.attribute(.paragraphStyle, at: headingOffset, effectiveRange: nil) as? NSParagraphStyle)

        XCTAssertEqual(displayed.string, body + heading)
        XCTAssertEqual(displayed.attribute(.font, at: 0, effectiveRange: nil) as? UIFont, bodyFont)
        XCTAssertEqual(displayed.attribute(.font, at: headingOffset, effectiveRange: nil) as? UIFont, headingFont)
        XCTAssertEqual(displayedBodyStyle.lineSpacing, 3)
        XCTAssertEqual(displayedBodyStyle.paragraphSpacing, 4)
        XCTAssertEqual(displayedHeadingStyle.paragraphSpacing, 5)
        XCTAssertEqual(displayedHeadingStyle.paragraphSpacingBefore, 11)
        XCTAssertNil(source.attribute(.paragraphStyle, at: 0, effectiveRange: nil))
    }

    func testWordDetailTableWrapsAtNarrowerDisplayWidth() throws {
        let longMeaning = String(repeating: "形容人或事物纷纷到来。", count: 10)
        let html = "<table><tr><th>成语</th><th>词义</th></tr>"
            + "<tr><td>纷至沓来</td><td><strong>\(longMeaning)</strong></td></tr></table><p>后续说明</p>"
        let original = NativeRichTextDisplayRenderer.render(html, tableAppearance: .wordDetail).attributedText
        let tableOffset = (original.string as NSString).range(of: "\u{FFFC}").location
        XCTAssertNotEqual(tableOffset, NSNotFound)
        guard tableOffset != NSNotFound else { return }
        let originalTable = try XCTUnwrap(original.attribute(.attachment, at: tableOffset, effectiveRange: nil) as? NSTextAttachment)

        let narrowed = NativeRichTextDisplayRenderer.applyingTableAppearance(to: original, appearance: .wordDetail, displayWidth: 210)
        let narrowTable = try XCTUnwrap(narrowed.attribute(.attachment, at: tableOffset, effectiveRange: nil) as? NSTextAttachment)

        XCTAssertEqual(narrowed.string, original.string)
        XCTAssertTrue(narrowed.string.contains("后续说明"))
        XCTAssertEqual(narrowTable.bounds.width, 210)
        XCTAssertGreaterThan(narrowTable.bounds.height, originalTable.bounds.height)
    }
}
