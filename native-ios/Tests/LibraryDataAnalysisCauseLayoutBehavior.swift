import Foundation

@main
enum LibraryDataAnalysisCauseLayoutBehavior {
    static func main() {
        let causes = LibraryDataAnalysisCauseLayout.splitLines(" 公式不熟悉 \r\n\n 看漏了平均 \n  ")
        precondition(causes == ["公式不熟悉", "看漏了平均"], "splits trimmed non-empty CRLF and LF lines")

        let sentence = LibraryDataAnalysisCauseLayout.splitLines("公式不熟悉，看漏了平均。")
        precondition(sentence == ["公式不熟悉，看漏了平均。"], "does not split punctuation in a sentence")

        let legacyCause: [String: Any] = ["cause": ["公式不熟悉", "", "看漏了平均"]]
        precondition(
            LibraryDataAnalysisCauseLayout.rawCause(in: legacyCause) == "公式不熟悉\n看漏了平均",
            "legacy cause arrays become trimmed non-empty lines"
        )
        precondition(
            LibraryDataAnalysisCauseLayout.rawCause(in: ["errorCause": "", "reason": "旧错因"]) == "",
            "an explicit empty canonical errorCause suppresses legacy aliases"
        )

        precondition(
            LibraryErrorCauseCompatibility.splitLines("公式不熟悉，看漏平均；单位换算") == ["公式不熟悉，看漏平均；单位换算"],
            "sentence punctuation remains part of a free-text cause"
        )
        precondition(
            LibraryErrorCauseCompatibility.splitLines(["公式不熟悉、看漏平均", "单位换算"]) == ["公式不熟悉", "看漏平均", "单位换算"],
            "legacy multi-tag values split only on the known old tag delimiter"
        )
        precondition(
            LibraryErrorCauseCompatibility.usesLineEditor(subject: "言语理解", module: "一、中心理解")
                && LibraryErrorCauseCompatibility.usesLineEditor(subject: "言语理解", module: "逻辑填空")
                && LibraryErrorCauseCompatibility.usesLineEditor(subject: "资料分析", module: "任意模块"),
            "the line editor is enabled only for the requested verbal modules and data analysis"
        )
        precondition(
            LibraryErrorCauseCompatibility.excludesFromCauseTagFiltering(subject: "言语理解", module: "中心理解")
                && LibraryErrorCauseCompatibility.excludesFromCauseTagFiltering(subject: "言语理解", module: "逻辑填空")
                && !LibraryErrorCauseCompatibility.excludesFromCauseTagFiltering(subject: "资料分析", module: "资料分析"),
            "only center understanding and logic fill remove free-text causes from tag filters"
        )

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
