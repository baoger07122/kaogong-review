import Foundation

@main
enum ExamDomainBehavior {
    static func main() {
        checksOfficialReportSample()
        checksSplitAndOptionalFields()
        checksUnknownAndConflictingRows()
        checksTimeParsing()
        checksMergePreservesManualValues()
        checksReviewSourcePolicy()
        print("Exam domain behavior checks passed")
    }

    private static func checksOfficialReportSample() {
        let report = """
        政治理论
        共20道，答对10道，正确率50%，用时8分15秒
        常识判断
        共15道，答对10道，正确率67%，用时4分54秒
        言语理解与表达
        共30道，答对20道，正确率67%，用时30分44秒
        逻辑填空
        共15道，答对10道，正确率67%，用时15分12秒
        片段阅读
        共9道，答对5道，正确率56%，用时10分6秒
        语句表达
        共6道，答对5道，正确率83%，用时5分26秒
        数量关系
        共10道，答对3道，正确率30%，用时23分42秒
        判断推理
        共35道，答对22道，正确率63%，用时38分42秒
        判断推理
        共35道，答对22道，正确率63%，用时38分42秒

        图形推理
        共10道，答对9道，正确率90%，用时15分3秒

        定义判断
        共10道，答对5道，正确率50%，用时9分26秒

        类比推理
        共5道，答对3道，正确率60%，用时4分36秒
        •
        逻辑判断
        共10道，答对5道，正确率50%，用时9分37秒

        资料分析
        共20道，答对16道，正确率80%，用时39分钟
        """
        let result = ExamReportParser.parse(report)
        check(result.lines.count == 13, "the pasted report should keep six summary rows and seven children")
        check(result.duplicateConflicts.isEmpty, "an exact repeated parent row should be de-duplicated")
        check(result.unparsedLines.isEmpty, "the pasted report should not leave title or data rows unparsed")
        let metrics = ExamReportParser.metrics(for: result.lines)
        check(metrics.totalQuestions == 130, "summary question total should be 130")
        check(metrics.correctCount == 81, "summary correct count should be 81")
        check(metrics.wrongCount == 49, "summary wrong count should be 49")
        check(metrics.totalTimeSeconds == 8_717, "summary time should be 8,717 seconds")
        check(result.lines.first(where: { $0.subject == "逻辑填空" })?.timeSeconds == "912", "language child time should parse")
        check(result.lines.first(where: { $0.subject == "逻辑判断" })?.timeSeconds == "577", "reasoning child time should parse")
    }

    private static func checksSplitAndOptionalFields() {
        let report = """
        逻辑填空
        共
        5 道，答对
        4 道
        正确率：
        80％
        用时：
        2分3秒
        判断推理 共4道，答对3道，用时01:02
        """
        let result = ExamReportParser.parse(report)
        check(result.lines.count == 2, "multi-line OCR fragments and same-line rows should parse")
        check(result.lines[0].reportedAccuracy == "80", "full-width percent should normalize")
        check(result.lines[0].timeSeconds == "123", "Chinese minute and second fragments should add")
        check(result.lines[1].timeSeconds == "62", "colon time without an accuracy should parse")

        let partial = ExamReportParser.parse("数量关系\n共5题，答对4题")
        check(partial.lines.first?.reportedAccuracy.isEmpty == true, "missing report accuracy should remain unknown")
        check(partial.lines.first?.timeSeconds.isEmpty == true, "missing time should remain unknown")
        check(ExamReportParser.metrics(for: partial.lines).accuracyPercent == 80, "overall accuracy should derive from total and correct counts")
        check(ExamReportParser.metrics(for: partial.lines).totalTimeSeconds == nil, "missing time should not be inferred")
    }

    private static func checksUnknownAndConflictingRows() {
        let unknown = ExamReportParser.parse("常识判断\n共5题答对3题\n新科目\n共2题答对1题")
        check(unknown.lines.count == 1 && unknown.lines[0].subject == "常识判断", "unknown rows must not attach to the previous subject")
        check(unknown.unparsedLines.contains("新科目") && unknown.unparsedLines.contains("共2题答对1题"), "unknown heading and data should remain visible")

        let inlineUnknown = ExamReportParser.parse("常识判断\n共5题答对3题\n新科目 共2题答对1题")
        check(inlineUnknown.lines.count == 1 && inlineUnknown.unparsedLines.contains("新科目 共2题答对1题"), "unknown same-line rows must remain unparsed")

        let conflict = ExamReportParser.parse("政治理论\n共5题答对3题\n政治理论\n共5题答对4题")
        check(conflict.lines.count == 2, "conflicting duplicate values should both remain for review")
        check(conflict.duplicateConflicts == ["政治理论"], "conflicting duplicate subject should be reported")

        let raw = "\r\n政治理论\r\n共 3 道、答对 2 道\r\n"
        let copy = raw
        _ = ExamReportParser.parse(raw)
        check(raw == copy, "parsing must not mutate the source report")
    }

    private static func checksTimeParsing() {
        check(ExamReportParser.parseTime("39分钟") == 2_340, "minute-only time should parse")
        check(ExamReportParser.parseTime("8分15秒") == 495, "Chinese minute and second time should parse")
        check(ExamReportParser.parseTime("01:02:03") == 3_723, "hour colon time should parse")
        check(ExamReportParser.parseTime("01：02") == 62, "full-width colon time should parse")
        check(ExamModuleCatalog.canonicalSubject("未知模块") == nil, "unknown module should not be mapped")
        check(ExamModuleCatalog.parentSubject(for: "逻辑填空") == "言语理解与表达", "known child module should have a fixed parent")
        check(!ExamModuleResult(subject: "历史自定义模块").isTopLevel, "unmapped historical modules must not enter an official summary")
    }

    private static func checksMergePreservesManualValues() {
        let existing = ExamModuleResult(
            id: "manual",
            subject: "政治理论",
            totalQuestions: "20",
            correctCount: "11",
            reportedAccuracy: "手工核对",
            timeSeconds: ""
        )
        let parsed = ExamModuleResult(
            subject: "政治理论",
            totalQuestions: "20",
            correctCount: "10",
            reportedAccuracy: "50",
            timeSeconds: "495"
        )
        let merged = ExamReportMergePolicy.merge([parsed], into: [existing])
        check(merged.lines.count == 1, "merge should update the matching module instead of duplicating it")
        check(merged.lines[0].id == "manual", "merge should preserve the existing row identity")
        check(merged.lines[0].correctCount == "11", "merge should preserve the manual non-empty count")
        check(merged.lines[0].reportedAccuracy == "手工核对", "merge should preserve manual accuracy text")
        check(merged.lines[0].timeSeconds == "495", "merge should fill an empty time field")
        check(merged.conflicts.contains("政治理论答对数"), "different non-empty values should be reported as conflicts")
    }

    private static func checksReviewSourcePolicy() {
        check(LibraryReviewSourcePolicy.classify(collection: "errors", object: [:]) == .real, "legacy errors without a marker should stay visible as real reviews")
        check(LibraryReviewSourcePolicy.classify(collection: "notes", object: [:]) == .real, "legacy notes without a marker should stay visible as real reviews")
        check(LibraryReviewSourcePolicy.classify(collection: "stickies", object: [:]) == .real, "legacy stickies without a marker should stay visible as real reviews")
        check(LibraryReviewSourcePolicy.classify(collection: "words", object: ["reviewSource": "mock"]) == .pending, "word bank should not enter source partitions")
        check(LibraryReviewSourcePolicy.classify(collection: "errors", object: ["type": "未分类"]) == .real, "domain type must not be mistaken for review source")
        check(LibraryReviewSourcePolicy.classify(collection: "errors", object: ["reviewSource": "pending"]) == .pending, "explicit pending source should remain pending")
        check(LibraryReviewSourcePolicy.classify(collection: "errors", object: ["questionBankPaperID": "paper"]) == .real, "question-bank records should remain real reviews")
        check(LibraryReviewSourcePolicy.classify(
            collection: "errors",
            object: ["questionBankPaperID": "paper", "reviewSource": "real"],
            linkedExamObject: ["examType": "mock"]
        ) == .mock, "a linked mock exam should override a stale real marker")
    }

    private static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError("Behavior check failed: \(message)") }
    }
}
