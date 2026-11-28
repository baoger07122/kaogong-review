import Foundation
import SwiftData

enum QuantityQuestionTypeRepository {
    private static let recordID = "quantity_question_types"

    private struct MutationSnapshot {
        let record: StoredRecord
        let payload: Data
        let indexPayload: Data?
        let module: String?
        let updatedAt: Date?
    }

    static func types(records: [StoredRecord]) -> [String] {
        let saved = storedTypes(records: records)
        let discovered = records.compactMap { record -> String? in
            guard record.subject == "数量关系" else { return nil }
            let value = (record.module ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, !QuantityQuestionTypeCatalog.legacyModules.contains(value) else { return nil }
            return value
        }
        return orderedUnique(saved + discovered)
    }

    static func contains(_ value: String?, records: [StoredRecord]) -> Bool {
        guard let value, !value.isEmpty else { return false }
        return types(records: records).contains(value)
    }

    static func add(_ name: String, records: [StoredRecord], context: ModelContext) throws {
        let value = clean(name)
        guard !value.isEmpty else { return }
        var values = types(records: records)
        guard !values.contains(value) else { return }
        values.append(value)
        try save(values, records: records, context: context)
    }

    static func move(_ name: String, direction: Int, records: [StoredRecord], context: ModelContext) throws {
        var values = types(records: records)
        guard let index = values.firstIndex(of: name) else { return }
        let destination = index + direction
        guard values.indices.contains(destination) else { return }
        values.swapAt(index, destination)
        try save(values, records: records, context: context)
    }

    static func rename(_ oldName: String, to newName: String, records: [StoredRecord], context: ModelContext) throws {
        let value = clean(newName)
        var values = types(records: records)
        guard let index = values.firstIndex(of: oldName), !value.isEmpty else { return }
        guard value == oldName || !values.contains(value) else { return }
        guard value != oldName else { return }
        values[index] = value
        try performTypeMutation(from: oldName, records: records, context: context) {
            try LibraryMistakeTagRepository.migrateQuantityTypeScope(
                from: oldName, to: value, records: records, context: context
            )
            try LibraryKnowledgePointGroupRepository.migrateQuantityTypeScope(
                from: oldName, to: value, records: records, context: context, save: false
            )
            try updateRecordModules(from: oldName, to: value, records: records)
            try renameTagLibraryKeys(from: oldName, to: value, records: records)
            try save(values, records: records, context: context, shouldSave: false)
        }
    }

    static func delete(_ name: String, records: [StoredRecord], context: ModelContext) throws {
        let values = types(records: records).filter { $0 != name }
        guard values.count != types(records: records).count else { return }
        try performTypeMutation(from: name, records: records, context: context) {
            try LibraryMistakeTagRepository.migrateQuantityTypeScope(
                from: name, to: nil, records: records, context: context
            )
            try LibraryKnowledgePointGroupRepository.migrateQuantityTypeScope(
                from: name, to: nil, records: records, context: context, save: false
            )
            try updateRecordModules(from: name, to: nil, records: records)
            try renameTagLibraryKeys(from: name, to: nil, records: records)
            try save(values, records: records, context: context, shouldSave: false)
        }
    }

    private static func storedTypes(records: [StoredRecord]) -> [String] {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID })?.jsonObject,
            let values = object["value"] as? [String]
        else { return [] }
        return orderedUnique(values.map(clean).filter { !$0.isEmpty })
    }

    private static func save(
        _ values: [String],
        records: [StoredRecord],
        context: ModelContext,
        shouldSave: Bool = true
    ) throws {
        let object: [String: Any] = ["key": recordID, "value": orderedUnique(values)]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
        }
        if shouldSave { try context.save() }
    }

    private static func updateRecordModules(from oldName: String, to newName: String?, records: [StoredRecord]) throws {
        for record in records where record.collection == "errors" {
            guard var object = record.jsonObject else { continue }
            let subject = nonEmpty(object["subject"] as? String)
                ?? nonEmpty(record.subject)
                ?? nonEmpty(record.indexObject?["subject"] as? String)
            let module = nonEmpty(object["module"] as? String)
                ?? nonEmpty(record.module)
                ?? nonEmpty(record.indexObject?["module"] as? String)
            guard subject == "数量关系", module == oldName else { continue }
            object["module"] = newName ?? ""
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.module = newName
            record.updatedAt = .now
        }
    }

    private static func renameTagLibraryKeys(from oldName: String, to newName: String?, records: [StoredRecord]) throws {
        for kind in ManagedTagKind.allCases where kind != .mistakeTag {
            let libraryRecordID = kind.recordID
            guard
                let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == libraryRecordID }),
                var object = record.jsonObject,
                var library = object["value"] as? [String: Any],
                let values = library.removeValue(forKey: oldName)
            else { continue }
            if let newName {
                let oldValues = values as? [String] ?? []
                let existingValues = library[newName] as? [String] ?? []
                library[newName] = orderedUnique(existingValues + oldValues)
            }
            object["value"] = library
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
        }
    }

    private static func performTypeMutation(
        from sourceModule: String,
        records: [StoredRecord],
        context: ModelContext,
        mutation: () throws -> Void
    ) throws {
        let snapshots = mutationSnapshots(from: sourceModule, records: records)
        let keyValueIDs = Set([
            recordID,
            LibraryKnowledgePointGroupRepository.recordID,
            LibraryMistakeTagRepository.recordID
        ] + ManagedTagKind.allCases.filter { $0 != .mistakeTag }.map(\.recordID))
        let existingKeyValueIDs = Set(records.compactMap { record -> String? in
            record.collection == "keyvalue" && keyValueIDs.contains(record.recordID) ? record.recordID : nil
        })

        do {
            try context.transaction { try mutation() }
        } catch {
            for snapshot in snapshots {
                snapshot.record.replacePayload(snapshot.payload, indexPayload: snapshot.indexPayload)
                snapshot.record.module = snapshot.module
                snapshot.record.updatedAt = snapshot.updatedAt
            }
            for insertedID in keyValueIDs.subtracting(existingKeyValueIDs) {
                let collection = "keyvalue"
                let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                    $0.collection == collection && $0.recordID == insertedID
                })
                for inserted in (try? context.fetch(descriptor)) ?? [] { context.delete(inserted) }
            }
            throw error
        }
    }

    private static func mutationSnapshots(from sourceModule: String, records: [StoredRecord]) -> [MutationSnapshot] {
        let keyValueIDs = Set([
            recordID,
            LibraryKnowledgePointGroupRepository.recordID,
            LibraryMistakeTagRepository.recordID
        ] + ManagedTagKind.allCases.filter { $0 != .mistakeTag }.map(\.recordID))
        return records.compactMap { record in
            let shouldCapture: Bool
            if record.collection == "keyvalue" {
                shouldCapture = keyValueIDs.contains(record.recordID)
            } else if record.collection == "errors" {
                let object = record.jsonObject ?? [:]
                let subject = nonEmpty(object["subject"] as? String)
                    ?? nonEmpty(record.subject)
                    ?? nonEmpty(record.indexObject?["subject"] as? String)
                let module = nonEmpty(object["module"] as? String)
                    ?? nonEmpty(record.module)
                    ?? nonEmpty(record.indexObject?["module"] as? String)
                shouldCapture = subject == "数量关系" && module == sourceModule
            } else {
                shouldCapture = false
            }
            guard shouldCapture else { return nil }
            return MutationSnapshot(
                record: record,
                payload: record.payload,
                indexPayload: record.indexPayload,
                module: record.module,
                updatedAt: record.updatedAt
            )
        }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = clean(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
