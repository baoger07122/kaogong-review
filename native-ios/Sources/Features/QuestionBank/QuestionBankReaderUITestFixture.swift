#if DEBUG
import Foundation
import SwiftData

enum QuestionBankReaderUITestFixture {
    static let launchArgument = "--question-bank-reader-ui-test"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
    private static let sessionArgumentPrefix = "--question-bank-reader-ui-test-session="
    private static var sessionID: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(sessionArgumentPrefix) })
            .map { String($0.dropFirst(sessionArgumentPrefix.count)) } ?? "missing-session"
    }
    static var paperID: String { "ui-test-\(sessionID)-paper" }
    static var moduleID: String { "ui-test-\(sessionID)-module" }
    static var materialID: String { "ui-test-\(sessionID)-material" }
    static var questionID: String { "ui-test-\(sessionID)-question-1" }

    @MainActor
    static func seed(in context: ModelContext) throws {
        let paperID = Self.paperID
        let moduleID = Self.moduleID
        let materialID = Self.materialID
        let paper = QuestionBankPaper(
            id: paperID,
            title: "交互测试题库",
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
            title: "阅读理解",
            instruction: "请选择正确选项。",
            originalPage: "1"
        )
        let material = QuestionBankMaterial(
            id: materialID,
            paperID: paperID,
            moduleID: moduleID,
            type: "文字材料",
            text: "用于检验共享材料分屏下的涂鸦命中区域。",
            imageAssetID: "",
            applicableQuestions: "1",
            originalPage: "1"
        )
        let question = QuestionBankQuestion(
            id: Self.questionID,
            paperID: paperID,
            moduleID: moduleID,
            number: 1,
            subject: "阅读理解",
            type: "纯文字",
            materialID: materialID,
            stem: "下列哪项是本题正确答案？____并保留连续空位__。",
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
            subject: "阅读理解",
            type: "单项选择题",
            materialID: "",
            stem: "用于检查涂鸦状态下不能跳到下一题。",
            stemImageAssetID: "",
            options: [
                QuestionBankOption(id: "A", text: "选项A", imageAssetID: ""),
                QuestionBankOption(id: "B", text: "选项B", imageAssetID: ""),
                QuestionBankOption(id: "C", text: "选项C", imageAssetID: ""),
                QuestionBankOption(id: "D", text: "选项D", imageAssetID: "")
            ],
            answer: "C",
            explanation: "交互测试夹具解析。",
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
        try context.save()
    }

    private static func insert<Value: Encodable>(
        _ value: Value,
        kind: String,
        id: String,
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        context.insert(QuestionBankRecord(
            compoundID: "\(paperID)::\(kind)::\(id)",
            paperID: QuestionBankReaderUITestFixture.paperID,
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
