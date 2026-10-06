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
        #else
        let usesQuestionBankUITestFixture = false
        #endif

        do {
            let container: ModelContainer
            if usesQuestionBankUITestFixture {
                let schema = Schema([StoredRecord.self, QuestionBankRecord.self])
                let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                container = try ModelContainer(for: schema, configurations: [configuration])
                #if DEBUG
                try QuestionBankReaderUITestFixture.seed(in: container.mainContext)
                #endif
            } else {
                // Add the question bank as a separate additive entity; existing records
                // (including the legacy 套卷 score collection) remain unchanged.
                container = try ModelContainer(for: StoredRecord.self, QuestionBankRecord.self)
                try OneTimeLocalDataReset.runIfNeeded(in: container)
                try TagPresetCleanupMigration.runIfNeeded(in: container)
            }
            modelContainer = container
        } catch {
            fatalError("无法初始化原生数据库：\(error.localizedDescription)")
        }
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
