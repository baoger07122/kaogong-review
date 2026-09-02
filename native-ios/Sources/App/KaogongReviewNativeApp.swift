import SwiftData
import SwiftUI

@main
struct KaogongReviewNativeApp: App {
    private let modelContainer: ModelContainer

    init() {
        do {
            let container = try ModelContainer(for: StoredRecord.self)
            try OneTimeLocalDataReset.runIfNeeded(in: container)
            modelContainer = container
        } catch {
            fatalError("无法初始化原生数据库：\(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(\.apiClient, .production)
        }
        .modelContainer(modelContainer)
    }
}
