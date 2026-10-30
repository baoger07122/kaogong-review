import Foundation

struct LocalBackupIntegrityReport: Equatable {
    let sourceCount: Int
    let restoredCount: Int
    let answerStateCount: Int
    let restoredAnswerStateCount: Int
    let mismatchedIDs: [String]

    var isComplete: Bool {
        mismatchedIDs.isEmpty && sourceCount == restoredCount && answerStateCount == restoredAnswerStateCount
    }

    var message: String {
        if isComplete {
            return "备份自检通过：\(sourceCount) 条本地记录和 \(answerStateCount) 条作答状态均可完整写入并重新解析"
        }
        let preview = mismatchedIDs.prefix(3).joined(separator: "、")
        return "备份自检发现异常：记录本地 \(sourceCount) 条、恢复包 \(restoredCount) 条；作答状态本地 \(answerStateCount) 条、恢复包 \(restoredAnswerStateCount) 条"
            + (preview.isEmpty ? "" : "；涉及 \(preview)")
    }
}

enum LocalBackupIntegrityChecker {
    static func check(
        records: [StoredRecord],
        answerStates: [QuestionBankAnswerStateBackup] = []
    ) throws -> LocalBackupIntegrityReport {
        let source = records.filter(isIncludedInBackup)
        let data = try LegacyBackupExporter.makeData(records: records, answerStates: answerStates)
        let package = try LegacyBackupImporter.parse(data: data)

        let sourcePayloads = try Dictionary(uniqueKeysWithValues: source.map {
            ($0.compoundID, try canonicalPayload($0.payload))
        })
        let restoredPayloads = try Dictionary(uniqueKeysWithValues: package.records.map {
            ($0.compoundID, try canonicalPayload($0.payload))
        })

        let allIDs = Set(sourcePayloads.keys).union(restoredPayloads.keys)
        let mismatches = allIDs.filter { sourcePayloads[$0] != restoredPayloads[$0] }.sorted()
        let sourceAnswerStates = Dictionary(uniqueKeysWithValues: answerStates.map { ($0.compoundID, $0) })
        let restoredAnswerStates = Dictionary(uniqueKeysWithValues: package.questionBankAnswerStates.map { ($0.compoundID, $0) })
        let answerStateIDs = Set(sourceAnswerStates.keys).union(restoredAnswerStates.keys)
        let answerStateMismatches = answerStateIDs
            .filter { sourceAnswerStates[$0] != restoredAnswerStates[$0] }
            .sorted()
            .map { "answer-state:\($0)" }
        return LocalBackupIntegrityReport(
            sourceCount: sourcePayloads.count,
            restoredCount: restoredPayloads.count,
            answerStateCount: sourceAnswerStates.count,
            restoredAnswerStateCount: restoredAnswerStates.count,
            mismatchedIDs: mismatches + answerStateMismatches
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
