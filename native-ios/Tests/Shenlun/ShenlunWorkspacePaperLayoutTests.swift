import UIKit
import XCTest
@testable import KaogongReviewNative

@MainActor
final class ShenlunWorkspacePaperLayoutTests: XCTestCase {
    func testLongMaterialWrapsWithinTheTextAreaAndKeepsEveryCharacter() throws {
        let passage = String(repeating: "这段材料说明如何整理走访中收集到的意见，并按主题归纳。", count: 85)
            + "最后一段的末句。"
        let layout = ShenlunWorkspacePaperLayout.material(title: "材料 1", text: passage)

        XCTAssertGreaterThan(layout.pages.count, 1)
        XCTAssertEqual(layout.pages.map(\.string).joined(), "材料 1\n" + passage)
        for page in layout.pages {
            XCTAssertGreaterThan(lineCountInsidePaper(for: page), 1)
        }

        let continuation = try XCTUnwrap(layout.pages.dropFirst().first)
        let style = try XCTUnwrap(continuation.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.firstLineHeadIndent, style.headIndent)
    }

    func testRequirementsUseTheSameFixedTextArea() throws {
        let question = ShenlunWorkspaceQuestion(
            practiceID: "practice",
            order: 0,
            title: "请从给定材料中梳理主要问题，并提出可操作的建议。",
            instructions: String(repeating: "内容全面，表述准确，层次清楚。", count: 20)
        )
        let page = try XCTUnwrap(ShenlunWorkspacePaperLayout.requirements(questions: [question]).pages.first)
        XCTAssertGreaterThan(lineCountInsidePaper(for: page), 3)
    }

    func testBodyStartsFlushAndPreservesExplicitParagraphSpaces() throws {
        let material = ShenlunWorkspacePaperLayout.material(title: "材料 1", text: "正文\n　手动缩进")
        let page = try XCTUnwrap(material.pages.first)
        let location = (page.string as NSString).range(of: "正文").location
        let style = try XCTUnwrap(page.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)
        XCTAssertEqual(style.firstLineHeadIndent, 0)
        XCTAssertTrue(page.string.contains("\n　手动缩进"))
        let question = ShenlunWorkspaceQuestion(practiceID: "practice", order: 0, title: "题干", instructions: "　作答要求")
        XCTAssertTrue(ShenlunWorkspacePaperLayout.requirements(questions: [question]).pages.map(\.string).joined().contains("\n　作答要求"))
    }

    private func lineCountInsidePaper(for page: NSAttributedString) -> Int {
        let size = ShenlunWorkspacePaperLayout.textSize
        let reader = ShenlunWorkspaceTextPaperPage(text: page).makeTextView()
        reader.frame = CGRect(origin: .zero, size: size)
        reader.layoutIfNeeded()

        XCTAssertTrue(reader.isSelectable)
        XCTAssertEqual(reader.textContainer.size, size)
        let manager = reader.layoutManager
        manager.ensureLayout(for: reader.textContainer)
        let glyphs = manager.glyphRange(for: reader.textContainer)
        let rendered = manager.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        XCTAssertEqual(rendered, NSRange(location: 0, length: page.length))

        var lines = 0
        manager.enumerateLineFragments(forGlyphRange: glyphs) { _, used, _, _, _ in
            XCTAssertGreaterThanOrEqual(used.minX, -1)
            XCTAssertLessThanOrEqual(used.maxX, size.width + 1)
            XCTAssertLessThanOrEqual(used.maxY, size.height + 1)
            lines += 1
        }
        return lines
    }
}
