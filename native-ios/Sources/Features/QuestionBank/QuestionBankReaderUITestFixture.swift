#if DEBUG
import Foundation
import SwiftData

enum QuestionBankReaderUITestFixture {
    static let launchArgument = "--question-bank-reader-ui-test"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
    private static let sessionArgumentPrefix = "--question-bank-reader-ui-test-session="
    private static let longContentArgument = "--question-bank-reader-ui-test-long-content"
    private static var sessionID: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(sessionArgumentPrefix) })
            .map { String($0.dropFirst(sessionArgumentPrefix.count)) } ?? "missing-session"
    }
    static var paperID: String { "ui-test-\(sessionID)-paper" }
    static var moduleID: String { "ui-test-\(sessionID)-module" }
    static var compactPaperID: String { "ui-test-\(sessionID)-compact-paper" }
    static var compactModuleID: String { "ui-test-\(sessionID)-compact-module" }
    static var materialID: String { "ui-test-\(sessionID)-material" }
    static var questionID: String { "ui-test-\(sessionID)-question-1" }

    @MainActor
    static func seed(in context: ModelContext) throws {
        let paperID = Self.paperID
        let moduleID = Self.moduleID
        let materialID = Self.materialID
        let longPaperTitle = "2025年度中央机关及其直属机构公务员录用考试行政职业能力测验（市地级及以下职位真题试卷）"
            + String(repeating: "长标题换行验证", count: 18)
        let paper = QuestionBankPaper(
            id: paperID,
            title: longPaperTitle,
            year: 2025,
            examType: "测试",
            volume: "交互夹具",
            source: "ui-test",
            importVersion: "1"
        )
        let module = QuestionBankModule(
            id: moduleID,
            paperID: paperID,
            sequence: 1,
            title: "五、资料分析",
            instruction: "请选择正确选项。",
            originalPage: "1"
        )
        let usesLongContent = ProcessInfo.processInfo.arguments.contains(longContentArgument)
        let materialText = usesLongContent
            ? String(repeating: "长材料用于验证单题模式保留纵向阅读；横向翻页时页面应锁定垂直位移。\n", count: 70)
            : "用于检验共享材料分屏下的涂鸦命中区域。"
        let questionStem = usesLongContent
            ? String(repeating: "长题干内容用于验证单题模式纵向阅读与横向翻页时垂直锁定。", count: 110)
            : "下列哪项是本题正确答案？____并保留连续空位__。"
        let material = QuestionBankMaterial(
            id: materialID,
            paperID: paperID,
            moduleID: moduleID,
            type: "文字材料",
            text: materialText,
            imageAssetID: "",
            applicableQuestions: "1-2",
            originalPage: "1"
        )
        let question = QuestionBankQuestion(
            id: Self.questionID,
            paperID: paperID,
            moduleID: moduleID,
            number: 1,
            subject: "行测",
            type: "纯文字",
            materialID: materialID,
            stem: questionStem,
            stemImageAssetID: "",
            options: [
                QuestionBankOption(id: "A", text: "用于测试的错误选项", imageAssetID: ""),
                QuestionBankOption(id: "B", text: "用于测试的正确选项", imageAssetID: ""),
                QuestionBankOption(id: "C", text: "用于测试的干扰选项", imageAssetID: ""),
                QuestionBankOption(id: "D", text: "另一项干扰选项", imageAssetID: "")
            ],
            answer: "B",
            explanation: "交互测试夹具解析。",
            originalPage: "1"
        )
        let nextQuestion = QuestionBankQuestion(
            id: "\(paperID)-question-2",
            paperID: paperID,
            moduleID: moduleID,
            number: 2,
            subject: "行测",
            type: "单项选择题",
            materialID: materialID,
            stem: "用于检查涂鸦状态下不能跳到下一题。",
            stemImageAssetID: "",
            options: [
                QuestionBankOption(id: "A", text: "选项A", imageAssetID: ""),
                QuestionBankOption(id: "B", text: "选项B", imageAssetID: ""),
                QuestionBankOption(id: "C", text: "选项C", imageAssetID: ""),
                QuestionBankOption(id: "D", text: "选项D", imageAssetID: "")
            ],
            answer: "",
            explanation: "交互测试夹具解析。",
            originalPage: "1"
        )
        let compactPaper = QuestionBankPaper(
            id: Self.compactPaperID,
            title: "2024国考真题",
            year: 2024,
            examType: "测试",
            volume: "跨卷偏好夹具",
            source: "ui-test",
            importVersion: "1"
        )
        let compactModule = QuestionBankModule(
            id: Self.compactModuleID,
            paperID: Self.compactPaperID,
            sequence: 1,
            title: "五、资料分析",
            instruction: "请选择正确选项。",
            originalPage: "1"
        )
        let compactQuestion = QuestionBankQuestion(
            id: "\(Self.compactPaperID)-question-1",
            paperID: Self.compactPaperID,
            moduleID: Self.compactModuleID,
            number: 1,
            subject: "资料分析",
            type: "单项选择题",
            materialID: "",
            stem: "用于验证阅读方式偏好会应用到另一张试卷。",
            stemImageAssetID: "",
            options: [
                QuestionBankOption(id: "A", text: "选项A", imageAssetID: ""),
                QuestionBankOption(id: "B", text: "选项B", imageAssetID: "")
            ],
            answer: "A",
            explanation: "跨试卷偏好夹具解析。",
            originalPage: "1"
        )

        try insert(paper, kind: QuestionBankRepository.paperKind, id: paperID,
                   year: paper.year, examType: paper.examType, title: paper.title,
                   searchText: paper.title, normalizedPaperKey: paper.duplicateKey, in: context)
        try insert(module, kind: QuestionBankRepository.moduleKind, id: moduleID,
                   moduleID: moduleID, sequence: module.sequence, title: module.title,
                   searchText: module.title, in: context)
        try insert(material, kind: QuestionBankRepository.materialKind, id: materialID,
                   moduleID: moduleID, title: "共用材料", searchText: material.text, in: context)
        try insert(question, kind: QuestionBankRepository.questionKind, id: question.id,
                   moduleID: moduleID, number: question.number, title: "第1题",
                   searchText: question.stem + " " + question.options.map(\.text).joined(separator: " "), in: context)
        try insert(nextQuestion, kind: QuestionBankRepository.questionKind, id: nextQuestion.id,
                   moduleID: moduleID, number: nextQuestion.number, title: "第2题",
                   searchText: nextQuestion.stem + " " + nextQuestion.options.map(\.text).joined(separator: " "), in: context)
        try insert(compactPaper, kind: QuestionBankRepository.paperKind, id: Self.compactPaperID,
                   paperID: Self.compactPaperID, year: compactPaper.year, examType: compactPaper.examType,
                   title: compactPaper.title, searchText: compactPaper.title,
                   normalizedPaperKey: compactPaper.duplicateKey, in: context)
        try insert(compactModule, kind: QuestionBankRepository.moduleKind, id: Self.compactModuleID,
                   paperID: Self.compactPaperID, moduleID: Self.compactModuleID,
                   sequence: compactModule.sequence, title: compactModule.title,
                   searchText: compactModule.title, in: context)
        try insert(compactQuestion, kind: QuestionBankRepository.questionKind, id: compactQuestion.id,
                   paperID: Self.compactPaperID, moduleID: Self.compactModuleID,
                   number: compactQuestion.number, title: "第1题",
                   searchText: compactQuestion.stem + " " + compactQuestion.options.map(\.text).joined(separator: " "),
                   in: context)
        try context.save()
    }

    private static func insert<Value: Encodable>(
        _ value: Value,
        kind: String,
        id: String,
        paperID: String? = nil,
        moduleID: String? = nil,
        number: Int? = nil,
        sequence: Int? = nil,
        year: Int? = nil,
        examType: String? = nil,
        title: String? = nil,
        searchText: String,
        normalizedPaperKey: String? = nil,
        in context: ModelContext
    ) throws {
        let resolvedPaperID = paperID ?? Self.paperID
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        context.insert(QuestionBankRecord(
            compoundID: "\(resolvedPaperID)::\(kind)::\(id)",
            paperID: resolvedPaperID,
            kind: kind,
            stableID: id,
            moduleID: moduleID,
            questionNumber: number,
            sequence: sequence,
            year: year,
            examType: examType,
            normalizedPaperKey: normalizedPaperKey,
            title: title,
            searchText: searchText,
            payload: try encoder.encode(value)
        ))
    }
}
#endif
