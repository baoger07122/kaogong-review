import Foundation
import SwiftData

enum LibraryLegacyIndexMigration {
    static let currentVersion = 1

    @MainActor
    static func runIfNeeded(in container: ModelContainer, storedVersion: Int) async throws -> Int {
        guard storedVersion < currentVersion else { return 0 }
        let started = ProcessInfo.processInfo.systemUptime
        let changed = try await Task.detached(priority: .utility) {
            let context = ModelContext(container)
            context.autosaveEnabled = false
            let descriptor = FetchDescriptor<StoredRecord>(
                predicate: #Predicate { record in
                    record.collection == "errors"
                        || record.collection == "words"
                }
            )
            let records = try context.fetch(descriptor)
            var changed = 0
            for record in records {
                let index = record.indexObject ?? [:]
                let payload = record.jsonObject ?? [:]
                let needsRepair: Bool
                if record.collection == "errors" {
                    needsRepair = (index["pitfall"] == nil && payload["pitfall"] != nil)
                        || (index["options"] == nil && payload["options"] != nil)
                } else {
                    needsRepair = index["entryKind"] == nil && payload["entryKind"] != nil
                }
                guard needsRepair else { continue }
                record.replacePayload(record.payload)
                changed += 1
            }
            if changed > 0 { try context.save() }
            return changed
        }.value
        NativePerformanceLog.mark("library legacy index migration changed=\(changed)", since: started)
        return changed
    }
}
