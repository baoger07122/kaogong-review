import Foundation
import SwiftData

enum LocalRestoreSafetyError: LocalizedError {
    case injectionDidNotFail
    case originalRecordWasNotRestored

    var errorDescription: String? {
        switch self {
        case .injectionDidNotFail:
            "故障注入未按预期中断恢复"
        case .originalRecordWasNotRestored:
            "恢复失败后，原有数据未完整回滚"
        }
    }
}

@MainActor
enum LocalRestoreSafetyChecker {
    private enum InjectedFailure: Error { case beforeSave }

    static func check() throws -> String {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: StoredRecord.self, configurations: configuration)
        let context = ModelContext(container)

        let originalPayload = try JSONSerialization.data(
            withJSONObject: ["id": "original", "title": "回滚前记录", "unknownField": "必须保留"],
            options: [.sortedKeys]
        )
        context.insert(StoredRecord(collection: "notes", recordID: "original", payload: originalPayload))
        try context.save()

        let replacementPayload = try JSONSerialization.data(
            withJSONObject: ["id": "replacement", "title": "不应写入"],
            options: [.sortedKeys]
        )
        let replacement = LegacyRecordDraft(
            collection: "notes",
            recordID: "replacement",
            payload: replacementPayload,
            subject: nil,
            module: nil,
            createdAt: nil,
            updatedAt: nil
        )
        let package = LegacyImportPackage(version: 1, records: [replacement], counts: ["notes": 1])

        var didInjectFailure = false
        do {
            try LegacyBackupRestorer.replace(with: package, in: context) {
                throw InjectedFailure.beforeSave
            }
        } catch is InjectedFailure {
            didInjectFailure = true
            context.rollback()
        }
        guard didInjectFailure else { throw LocalRestoreSafetyError.injectionDidNotFail }

        let records = try context.fetch(FetchDescriptor<StoredRecord>())
        guard records.count == 1,
              let original = records.first,
              original.compoundID == "notes:original",
              original.payload == originalPayload else {
            throw LocalRestoreSafetyError.originalRecordWasNotRestored
        }
        return "恢复安全自检通过：模拟覆盖中断后，原有记录已完整回滚"
    }
}
