import Foundation

struct LocalBackupIntegrityReport: Equatable {
    let sourceCount: Int
    let restoredCount: Int
    let mismatchedIDs: [String]

    var isComplete: Bool { mismatchedIDs.isEmpty && sourceCount == restoredCount }

    var message: String {
        if isComplete {
            return "备份自检通过：\(sourceCount) 条本地记录均可完整写入并重新解析"
        }
        let preview = mismatchedIDs.prefix(3).joined(separator: "、")
        return "备份自检发现异常：本地 \(sourceCount) 条，恢复包 \(restoredCount) 条"
            + (preview.isEmpty ? "" : "；涉及 \(preview)")
    }
}

enum LocalBackupIntegrityChecker {
    static func check(records: [StoredRecord]) throws -> LocalBackupIntegrityReport {
        let source = records.filter(isIncludedInBackup)
        let data = try LegacyBackupExporter.makeData(records: records)
        let package = try LegacyBackupImporter.parse(data: data)

        let sourcePayloads = try Dictionary(uniqueKeysWithValues: source.map {
            ($0.compoundID, try canonicalPayload($0.payload))
        })
        let restoredPayloads = try Dictionary(uniqueKeysWithValues: package.records.map {
            ($0.compoundID, try canonicalPayload($0.payload))
        })

        let allIDs = Set(sourcePayloads.keys).union(restoredPayloads.keys)
        let mismatches = allIDs.filter { sourcePayloads[$0] != restoredPayloads[$0] }.sorted()
        return LocalBackupIntegrityReport(
            sourceCount: sourcePayloads.count,
            restoredCount: restoredPayloads.count,
            mismatchedIDs: mismatches
        )
    }

    private static func isIncludedInBackup(_ record: StoredRecord) -> Bool {
        return !(record.collection == "keyvalue" && record.recordID.hasPrefix("auto_backup_"))
    }

    private static func canonicalPayload(_ data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
    }
}
