import Foundation
import SwiftData

enum OneTimeLocalDataReset {
    static let markerKey = "native.recoveryReset.9.2.5"

    static func runIfNeeded(in container: ModelContainer) throws {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: markerKey) else { return }

        let context = ModelContext(container)
        context.autosaveEnabled = false
        let records = try context.fetch(FetchDescriptor<StoredRecord>())
        records.forEach(context.delete)
        try context.save()

        try? KeychainTokenStore().delete()
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("native.") {
            defaults.removeObject(forKey: key)
        }
        defaults.set(true, forKey: markerKey)
    }
}
