import Foundation
import SwiftData

/// Stores new verbal-reasoning knowledge points under their stable error-type IDs.
/// The existing module-only `kp_library` record remains the legacy bucket.
enum VerbalReasoningKnowledgePointRepository {
    static let recordID = "verbal_reasoning_knowledge_points_by_type"

    static func tags(module: String, typeID: String, records: [StoredRecord]) -> [String] {
        VerbalReasoningKnowledgePointLibraryPolicy.tags(
            from: libraryValue(records: records),
            module: module,
            typeID: typeID
        )
    }

    static func migrateLegacy(
        _ rawName: String,
        module: String,
        toTypeID typeID: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty,
              LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
                .contains(where: { $0.module == module && $0.id == typeID }) else { return }

        let legacyRecordID = ManagedTagKind.knowledgePoint.recordID
        let legacyRecord = records.first { $0.collection == "keyvalue" && $0.recordID == legacyRecordID }
        var legacyValue = legacyRecord?.jsonObject?["value"] as? [String: Any] ?? [:]
        let legacyNames = legacyValue[module] as? [String] ?? []
        guard legacyNames.contains(name) else { return }

        var typedGroups = loadGroups(records: records)
        let destinationNames = typedGroups[module]?[typeID] ?? []
        if !destinationNames.contains(name) { typedGroups[module, default: [:]][typeID, default: []].append(name) }

        var changes: [RecordChange] = []
        var hasAmbiguousLegacyReference = false
        for record in records where record.collection == "errors"
            && (record.subject ?? record.indexObject?["subject"] as? String) == "言语理解" {
            let moduleValues = [record.module, record.indexObject?["module"] as? String]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            guard moduleValues.first == module, var object = record.jsonObject else { continue }
            let references = LibraryKnowledgePointReferencePolicy.references(from: object)
            let plan = VerbalLegacyKnowledgePointMigrationPolicy.plan(
                references: references,
                recordModule: moduleValues.first,
                recordTypeID: object["errorTypeID"] as? String,
                sourceModule: module,
                name: name,
                destinationTypeID: typeID
            )
            hasAmbiguousLegacyReference = hasAmbiguousLegacyReference || plan.hasAmbiguousLegacyReference
            guard plan.didChange else { continue }

            let unique = plan.references
            let displayNames = LibraryKnowledgePointReferencePolicy.displayNames(from: unique)
            object["knowledgePointRefs"] = unique.map(\.jsonValue)
            object["knowledgePoints"] = displayNames
            object["knowledgePoint"] = displayNames.joined(separator: "、")
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            changes.append(RecordChange(
                record: record,
                beforePayload: record.payload,
                beforeIndexPayload: record.indexPayload,
                beforeUpdatedAt: record.updatedAt,
                afterPayload: payload,
                afterIndexPayload: StoredRecord.makeIndexPayload(from: payload, collection: record.collection),
                updatedAt: .now
            ))
        }

        if !hasAmbiguousLegacyReference {
            let remaining = legacyNames.filter { $0 != name }
            if remaining.isEmpty { legacyValue.removeValue(forKey: module) }
            else { legacyValue[module] = remaining }
        }

        let legacySnapshot = legacyRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let typedRecord = records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
        let typedSnapshot = typedRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let groupSnapshot = groupRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }

        do {
            try context.transaction {
                if !hasAmbiguousLegacyReference {
                    try persistLegacy(legacyValue, record: legacyRecord, context: context, save: false)
                    try LibraryKnowledgePointGroupRepository.renameTagMember(
                        name, to: nil, subject: "言语理解", module: module, records: records, context: context, save: false
                    )
                }
                try persist(typedGroups, records: records, context: context, save: false)
                for change in changes {
                    change.record.replacePayload(change.afterPayload, indexPayload: change.afterIndexPayload)
                    change.record.updatedAt = change.updatedAt
                }
            }
        } catch {
            restoreKeyValueRecord(legacyRecord, snapshot: legacySnapshot, recordID: legacyRecordID, context: context)
            restoreKeyValueRecord(typedRecord, snapshot: typedSnapshot, recordID: recordID, context: context)
            restoreKeyValueRecord(groupRecord, snapshot: groupSnapshot,
                                  recordID: LibraryKnowledgePointGroupRepository.recordID, context: context)
            for change in changes {
                change.record.replacePayload(change.beforePayload, indexPayload: change.beforeIndexPayload)
                change.record.updatedAt = change.beforeUpdatedAt
            }
            throw error
        }
    }

    static func add(
        _ rawName: String,
        module: String,
        typeID: String,
        records: [StoredRecord],
        context: ModelContext,
        groupID: String? = nil
    ) throws {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var groups = loadGroups(records: records)
        guard !(groups[module]?[typeID] ?? []).contains(name) else { return }
        groups[module, default: [:]][typeID, default: []].append(name)
        guard let groupID else {
            try persist(groups, records: records, context: context)
            return
        }
        let libraryRecord = records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
        let librarySnapshot = libraryRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let groupSnapshot = groupRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        do {
            try context.transaction {
                try persist(groups, records: records, context: context, save: false)
                try LibraryKnowledgePointGroupRepository.addTagToGroup(
                    name, groupID: groupID, subject: "言语理解", module: module, typeID: typeID,
                    records: records, context: context, save: false
                )
            }
        } catch {
            restoreKeyValueRecord(libraryRecord, snapshot: librarySnapshot, recordID: recordID, context: context)
            restoreKeyValueRecord(groupRecord, snapshot: groupSnapshot,
                                  recordID: LibraryKnowledgePointGroupRepository.recordID, context: context)
            throw error
        }
    }

    static func reorder(
        _ names: [String],
        module: String,
        typeID: String,
        records: [StoredRecord],
        context: ModelContext,
        groupID: String? = nil
    ) throws {
        var groups = loadGroups(records: records)
        let existing = groups[module]?[typeID] ?? []
        let order = LibraryKnowledgePointGroupRepository.mergedOrder(
            displayedOrder: names, groupID: groupID, fullOrder: existing,
            subject: "言语理解", module: module, typeID: typeID, records: records
        )
        guard order.count == existing.count, Set(order) == Set(existing), order != existing else { return }
        groups[module, default: [:]][typeID] = order
        try persist(groups, records: records, context: context)
    }

    @discardableResult
    static func rename(
        _ oldName: String,
        to rawNewName: String,
        module: String,
        typeID: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        let newName = rawNewName.trimmingCharacters(in: .whitespacesAndNewlines)
        var groups = loadGroups(records: records)
        let current = groups[module]?[typeID] ?? []
        guard !newName.isEmpty, newName != oldName, !current.contains(newName), current.contains(oldName) else {
            return result(module: module, typeID: typeID, oldName: oldName, newName: newName, changes: [])
        }
        groups[module, default: [:]][typeID] = current.map { $0 == oldName ? newName : $0 }
        return try mutate(
            groups,
            oldName: oldName,
            newName: newName,
            module: module,
            typeID: typeID,
            records: records,
            context: context
        )
    }

    @discardableResult
    static func delete(
        _ name: String,
        module: String,
        typeID: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        var groups = loadGroups(records: records)
        let current = groups[module]?[typeID] ?? []
        guard current.contains(name) else {
            return result(module: module, typeID: typeID, oldName: name, newName: nil, changes: [])
        }
        groups[module, default: [:]][typeID] = current.filter { $0 != name }
        return try mutate(
            groups,
            oldName: name,
            newName: nil,
            module: module,
            typeID: typeID,
            records: records,
            context: context
        )
    }

    private struct RecordChange {
        let record: StoredRecord
        let beforePayload: Data
        let beforeIndexPayload: Data?
        let beforeUpdatedAt: Date?
        let afterPayload: Data
        let afterIndexPayload: Data?
        let updatedAt: Date
    }

    private static func mutate(
        _ groups: [String: [String: [String]]],
        oldName: String,
        newName: String?,
        module: String,
        typeID: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        let changes = try prepareReferenceChanges(
            oldName: oldName,
            newName: newName,
            module: module,
            typeID: typeID,
            records: records
        )
        let libraryRecord = records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
        let librarySnapshot = libraryRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let groupSnapshot = groupRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }

        do {
            try context.transaction {
                try persist(groups, records: records, context: context, save: false)
                try LibraryKnowledgePointGroupRepository.renameTagMember(
                    oldName, to: newName, subject: "言语理解", module: module, typeID: typeID,
                    records: records, context: context, save: false
                )
                for change in changes {
                    change.record.replacePayload(change.afterPayload, indexPayload: change.afterIndexPayload)
                    change.record.updatedAt = change.updatedAt
                }
            }
        } catch {
            for change in changes {
                change.record.replacePayload(change.beforePayload, indexPayload: change.beforeIndexPayload)
                change.record.updatedAt = change.beforeUpdatedAt
            }
            if let libraryRecord, let librarySnapshot {
                libraryRecord.replacePayload(librarySnapshot.0, indexPayload: librarySnapshot.1)
                libraryRecord.updatedAt = librarySnapshot.2
            } else if libraryRecord == nil {
                let key = recordID
                let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                    $0.collection == "keyvalue" && $0.recordID == key
                })
                for inserted in (try? context.fetch(descriptor)) ?? [] { context.delete(inserted) }
            }
            restoreKeyValueRecord(groupRecord, snapshot: groupSnapshot,
                                  recordID: LibraryKnowledgePointGroupRepository.recordID, context: context)
            throw error
        }

        return result(
            module: module,
            typeID: typeID,
            oldName: oldName,
            newName: newName,
            changes: changes.map {
                LibraryTagRecordPayloadChange(
                    collection: $0.record.collection,
                    recordID: $0.record.recordID,
                    beforePayload: $0.beforePayload,
                    afterPayload: $0.afterPayload
                )
            }
        )
    }

    private static func prepareReferenceChanges(
        oldName: String,
        newName: String?,
        module: String,
        typeID: String,
        records: [StoredRecord]
    ) throws -> [RecordChange] {
        let now = Date.now
        var changes: [RecordChange] = []
        for record in records where record.collection == "errors"
            && (record.subject ?? record.indexObject?["subject"] as? String) == "言语理解" {
            guard var object = record.jsonObject else { continue }
            let references = LibraryKnowledgePointReferencePolicy.references(from: object)
            let hasMatch = references.contains {
                $0.module == module && $0.typeID == typeID && $0.name == oldName
            }
            guard hasMatch else { continue }
            let updated = references.compactMap { reference -> LibraryKnowledgePointReference? in
                guard reference.module == module, reference.typeID == typeID, reference.name == oldName else {
                    return reference
                }
                guard let newName else { return nil }
                return LibraryKnowledgePointReference(module: module, typeID: typeID, name: newName)
            }
            let unique = LibraryKnowledgePointReferencePolicy.uniqueReferences(updated)
            let names = LibraryKnowledgePointReferencePolicy.displayNames(from: unique)
            object["knowledgePointRefs"] = unique.map(\.jsonValue)
            object["knowledgePoints"] = names
            object["knowledgePoint"] = names.first ?? ""
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            changes.append(RecordChange(
                record: record,
                beforePayload: record.payload,
                beforeIndexPayload: record.indexPayload,
                beforeUpdatedAt: record.updatedAt,
                afterPayload: payload,
                afterIndexPayload: StoredRecord.makeIndexPayload(from: payload, collection: record.collection),
                updatedAt: now
            ))
        }
        return changes
    }

    private static func result(
        module: String,
        typeID: String,
        oldName: String,
        newName: String?,
        changes: [LibraryTagRecordPayloadChange]
    ) -> LibraryTagMutationResult {
        var value = LibraryTagMutationResult(
            kind: .knowledgePoint,
            module: module,
            oldName: oldName,
            newName: newName,
            recordChanges: changes
        )
        value.typeID = typeID
        return value
    }

    private static func loadGroups(records: [StoredRecord]) -> [String: [String: [String]]] {
        guard let value = libraryValue(records: records) else { return [:] }
        return value.reduce(into: [:]) { result, moduleEntry in
            guard let rawGroups = moduleEntry.value as? [String: Any] else { return }
            result[moduleEntry.key] = rawGroups.reduce(into: [:]) { groups, typeEntry in
                if let names = typeEntry.value as? [String] {
                    groups[typeEntry.key] = names
                }
            }
        }
    }

    private static func libraryValue(records: [StoredRecord]) -> [String: Any]? {
        records.first { $0.collection == "keyvalue" && $0.recordID == recordID }?.jsonObject?["value"] as? [String: Any]
    }

    private static func persist(
        _ groups: [String: [String: [String]]],
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        let object: [String: Any] = ["key": recordID, "value": groups]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
        }
        if shouldSave { try context.save() }
    }

    private static func persistLegacy(
        _ value: [String: Any],
        record: StoredRecord?,
        context: ModelContext,
        save shouldSave: Bool
    ) throws {
        let payload = try JSONSerialization.data(
            withJSONObject: ["key": ManagedTagKind.knowledgePoint.recordID, "value": value],
            options: [.sortedKeys]
        )
        if let record {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(
                collection: "keyvalue", recordID: ManagedTagKind.knowledgePoint.recordID,
                payload: payload, updatedAt: .now
            ))
        }
        if shouldSave { try context.save() }
    }

    private static func restoreKeyValueRecord(
        _ record: StoredRecord?,
        snapshot: (Data, Data?, Date?)?,
        recordID: String,
        context: ModelContext
    ) {
        if let record, let snapshot {
            record.replacePayload(snapshot.0, indexPayload: snapshot.1)
            record.updatedAt = snapshot.2
        } else if record == nil {
            let key = recordID
            let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                $0.collection == "keyvalue" && $0.recordID == key
            })
            for inserted in (try? context.fetch(descriptor)) ?? [] { context.delete(inserted) }
        }
    }
}
