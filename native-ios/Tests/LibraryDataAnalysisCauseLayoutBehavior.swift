import Foundation

@main
enum LibraryDataAnalysisCauseLayoutBehavior {
    static func main() {
        let causes = LibraryDataAnalysisCauseLayout.splitLines(" 公式不熟悉 \r\n\n 看漏了平均 \n  ")
        precondition(causes == ["公式不熟悉", "看漏了平均"], "splits trimmed non-empty CRLF and LF lines")

        let sentence = LibraryDataAnalysisCauseLayout.splitLines("公式不熟悉，看漏了平均。")
        precondition(sentence == ["公式不熟悉，看漏了平均。"], "does not split punctuation in a sentence")

        let wideLine = LibraryDataAnalysisCauseLayout.estimatedTagLineHeight(
            label: "错因", values: causes, width: 300
        )
        let narrowLine = LibraryDataAnalysisCauseLayout.estimatedTagLineHeight(
            label: "错因", values: causes, width: 100
        )
        precondition(wideLine > 0, "estimates a visible cause row")
        precondition(narrowLine > wideLine, "accounts for wrapped rows in narrow cards")

        let longCause = LibraryDataAnalysisCauseLayout.estimatedTagLineHeight(
            label: "错因", values: [String(repeating: "计算过程需要仔细核对", count: 5)], width: 140
        )
        precondition(longCause > narrowLine, "accounts for a long cause wrapping inside its tag")
    }
}
