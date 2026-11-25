#if DEBUG
import Foundation
import SwiftData

enum ShenlunReaderUITestFixture {
    static let launchArgument = "--shenlun-reader-ui-test"
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains(launchArgument) }
    private static let sessionPrefix = "--shenlun-reader-ui-test-session="
    private static var sessionID: String {
        ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(sessionPrefix) })
            .map { String($0.dropFirst(sessionPrefix.count)) } ?? "missing-session"
    }

    static var practiceID: String { "ui-test-\(sessionID)-practice" }
    static var questionID: String { "ui-test-\(sessionID)-question" }
    static var materialID: String { "ui-test-\(sessionID)-material" }
    static var layerID: String { "ui-test-\(sessionID)-layer" }

    @MainActor
    static func seed(in context: ModelContext) throws {
        guard try ShenlunWorkspaceRepository.practice(id: practiceID, in: context) == nil else { return }
        let layer = ShenlunWorkspaceLayer(id: layerID, name: "交互测试批注")
        let material = ShenlunWorkspaceMaterial(
            id: materialID,
            practiceID: practiceID,
            title: "缩放测试材料",
            order: 0,
            text: String(repeating: "材料文字用于验证纸面缩放、滚动和批注坐标共用同一比例。\n", count: 40),
            layers: [layer],
            activeLayerID: layerID,
            showAllLayers: true
        )
        let question = ShenlunWorkspaceQuestion(
            id: questionID,
            practiceID: practiceID,
            order: 0,
            title: "检查材料缩放与复盘切换",
            type: .essay,
            instructions: "在答案页与本次复盘页之间切换并分别保存。",
            fullScore: 20,
            maximumWordCount: 400,
            materialIDs: [materialID],
            materialDecisionMade: true
        )
        let practice = ShenlunWorkspacePractice(
            id: practiceID,
            name: "申论缩放交互测试",
            kind: .single,
            questionIDs: [questionID],
            materialIDs: [materialID],
            materialDecisionMade: true
        )
        try ShenlunWorkspaceRepository.saveNewPractice(
            practice, questions: [question], materials: [material], assets: [], in: context
        )
    }
}
#endif
