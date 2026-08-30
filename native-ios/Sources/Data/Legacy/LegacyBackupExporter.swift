import Foundation
import SwiftUI
import UniformTypeIdentifiers

struct BackupJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum LegacyBackupExporter {
    private static let collectionMappings: [(native: String, backup: String)] = [
        ("errors", "errors"),
        ("notes", "notes"),
        ("exams", "exams"),
        ("todos", "todos"),
        ("subject_reviews", "subjectReviews"),
        ("words", "words"),
        ("stickies", "stickies")
    ]

    static func makeDocument(records: [StoredRecord]) throws -> BackupJSONDocument {
        BackupJSONDocument(data: try makeData(records: records))
    }

    static func makeData(records: [StoredRecord]) throws -> Data {
        var root: [String: Any] = [
            "version": 1,
            "app": "kaogong-review",
            "exportedAt": ISO8601DateFormatter().string(from: .now)
        ]

        for mapping in collectionMappings {
            root[mapping.backup] = try records
                .filter { $0.collection == mapping.native }
                .sorted(by: stableRecordOrder)
                .map(payloadObject)
        }

        let keyValues = records
            .filter {
                $0.collection == "keyvalue"
                    && !$0.recordID.hasPrefix("auto_backup_")
                    && $0.recordID != "legacy.countdown"
                    && $0.recordID != "legacy.noteTypes"
            }
            .sorted(by: stableRecordOrder)
        root["keyvalue"] = try keyValues.map(payloadObject)
        root["countdown"] = try topLevelValue(id: "legacy.countdown", records: records) ?? []
        root["noteTypes"] = try topLevelValue(id: "legacy.noteTypes", records: records) ?? NSNull()

        guard JSONSerialization.isValidJSONObject(root) else {
            throw CocoaError(.propertyListWriteInvalid)
        }
        return try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private static func payloadObject(_ record: StoredRecord) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: record.payload) as? [String: Any] else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return object
    }

    private static func topLevelValue(id: String, records: [StoredRecord]) throws -> Any? {
        guard let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == id }) else {
            return nil
        }
        return try payloadObject(record)["value"]
    }

    private static func stableRecordOrder(_ lhs: StoredRecord, _ rhs: StoredRecord) -> Bool {
        let leftDate = lhs.createdAt ?? lhs.updatedAt ?? .distantPast
        let rightDate = rhs.createdAt ?? rhs.updatedAt ?? .distantPast
        return leftDate == rightDate ? lhs.recordID < rhs.recordID : leftDate < rightDate
    }
}
