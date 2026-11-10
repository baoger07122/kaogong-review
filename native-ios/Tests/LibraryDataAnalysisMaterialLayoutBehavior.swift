import Foundation

@main
struct LibraryDataAnalysisMaterialLayoutBehavior {
    static func main() {
        let source = "  已有两格缩进\r\n未缩进正文  保留连续空格\r\n\r\n第三段"
        let paragraphs = LibraryDataAnalysisMaterialLayout.paragraphs(from: source)
        expect(paragraphs.map(\.text) == ["  已有两格缩进", "未缩进正文  保留连续空格", "", "第三段"], "normalize newline variants and preserve spaces and blank lines")
        expect(!paragraphs[0].usesDefaultFirstLineIndent, "an existing leading indent must not receive a second indent")
        expect(paragraphs[1].usesDefaultFirstLineIndent, "an unindented paragraph receives a display-only first-line indent")
        expect(!paragraphs[2].usesDefaultFirstLineIndent, "blank lines do not receive indentation")

        let html = LibraryDataAnalysisMaterialLayout.paragraphs(from: "<p>&nbsp;&nbsp;甲 &amp; 乙</p><p>第二段<br>续行</p>")
        expect(html.map(\.text) == ["\u{00A0}\u{00A0}甲 & 乙", "第二段", "续行", ""], "HTML paragraphs, line breaks and space entities keep their meaning")
        expect(!html[0].usesDefaultFirstLineIndent, "HTML space entities count as existing indentation")
        expect(LibraryDataAnalysisMaterialLayout.paragraphs(from: " \t\u{3000}").allSatisfy { !$0.usesDefaultFirstLineIndent }, "whitespace-only materials do not receive a display indent")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
