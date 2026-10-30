import Foundation
import SwiftData
import SwiftUI

@main
struct KaogongReviewNativeApp: App {
    private let modelContainer: ModelContainer
    @StateObject private var questionBankImportRouter = QuestionBankImportRouter()

    init() {
        #if DEBUG
        let usesQuestionBankUITestFixture = QuestionBankReaderUITestFixture.isEnabled
        if usesQuestionBankUITestFixture {
            // Reset explicitly because CI can reuse a simulator between UI tests.
            UserDefaults.standard.set(
                false,
                forKey: QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey
            )
        }
        #endif

        do {
            #if DEBUG
            if usesQuestionBankUITestFixture {
                let schema = Schema([
                    StoredRecord.self, QuestionBankRecord.self,
                    QuestionBankBatchRecord.self, QuestionBankBatchSourceRecord.self,
                    QuestionBankBatchMaterialLinkRecord.self, QuestionBankBatchQuestionLinkRecord.self,
                    QuestionBankCatalogPaperRecord.self, QuestionBankCatalogModuleRecord.self,
                    QuestionBankCatalogQuestionRecord.self, QuestionBankCatalogProgressRecord.self,
                    QuestionBankAnswerStateRecord.self, QuestionBankAnswerStateMigrationRecord.self,
                    QuestionBankAnswerStateScopeClearRecord.self,
                    QuestionBankImportJobRecord.self
                ])
                let configuration = ModelConfiguration(
                    "QuestionBankReaderUITests-\(QuestionBankReaderUITestFixture.paperID)",
                    schema: schema,
                    url: try QuestionBankReaderUITestFixture.storeURL(),
                    cloudKitDatabase: .none
                )
                let container = try ModelContainer(for: schema, configurations: [configuration])
                try QuestionBankReaderUITestFixture.seed(in: container.mainContext)
                modelContainer = container
            } else {
                modelContainer = try Self.makeDefaultModelContainer()
            }
            #else
            modelContainer = try Self.makeDefaultModelContainer()
            #endif
        } catch {
            fatalError("无法初始化原生数据库：\(error.localizedDescription)")
        }
    }

    private static func makeDefaultModelContainer() throws -> ModelContainer {
        // Add question-bank, batch, and lightweight-catalog entities; existing records
        // (including the legacy 套卷 score collection) remain unchanged.
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
        try OneTimeLocalDataReset.runIfNeeded(in: container)
        try TagPresetCleanupMigration.runIfNeeded(in: container)
        return container
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(questionBankImportRouter)
                .environment(\.apiClient, .production)
                .environment(\.locale, Locale(identifier: "zh-Hans"))
                .onOpenURL { url in
                    questionBankImportRouter.receive(url)
                }
        }
        .modelContainer(modelContainer)
    }
}
