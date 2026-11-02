import SwiftData
import SwiftUI

@main
struct KaogongReviewNativeApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try Self.makeDefaultModelContainer()
        } catch {
            fatalError("无法初始化原生数据库：\(error.localizedDescription)")
        }
    }

    private static func makeDefaultModelContainer() throws -> ModelContainer {
        // Keep the historical entities in the schema so existing local stores remain
        // readable. The independent question-bank UI and its startup services are inert.
        let container = try ModelContainer(
            for: StoredRecord.self, QuestionBankRecord.self,
            QuestionBankBatchRecord.self, QuestionBankBatchSourceRecord.self,
            QuestionBankBatchMaterialLinkRecord.self, QuestionBankBatchQuestionLinkRecord.self,
            QuestionBankCatalogPaperRecord.self, QuestionBankCatalogModuleRecord.self,
            QuestionBankCatalogQuestionRecord.self, QuestionBankCatalogProgressRecord.self,
            QuestionBankAnswerStateRecord.self, QuestionBankAnswerStateMigrationRecord.self,
            QuestionBankAnswerStateScopeClearRecord.self,
            QuestionBankImportJobRecord.self
        )
        try TagPresetCleanupMigration.runIfNeeded(in: container)
        return container
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.apiClient, .production)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
        }
        .modelContainer(modelContainer)
    }
}
