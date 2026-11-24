import Foundation
import SwiftData

enum LibraryMistakeTagRepository {
    static let recordID = "library_mistake_tags_by_type_v1"

    private struct PendingRecordChange {
        let record: StoredRecord
        let beforePayload: Data
        let beforeIndexPayload: Data?
        let beforeUpdatedAt: Date?
        let afterPayload: Data
        let afterIndexPayload: Data?
        let updatedAt: Date
    }

    static func tags(
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord]
    ) -> [String] {
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        return catalog(records: records)[scope] ?? []
    }

    static func stageMembership(
        _ name: String, subject: String, module: String, typeID: String?, isPresent: Bool,
        records: [StoredRecord], context: ModelContext
    ) throws {
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        let existing = values[scope] ?? []
        guard existing.contains(name) != isPresent else { return }
        values[scope] = isPresent ? existing + [name] : existing.filter { $0 != name }
        try persist(values, records: records, context: context, save: false)
    }

    static func migrateQuantityTypeScope(
        from sourceModule: String,
        to destinationModule: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let destinationModule = destinationModule ?? ""
        guard sourceModule != destinationModule else { return }

        let sourceScope = LibraryMistakeTagPolicy.scopeKey(
            subject: "数量关系", module: sourceModule, typeID: nil
        )
        let destinationScope = LibraryMistakeTagPolicy.scopeKey(
            subject: "数量关系", module: destinationModule, typeID: nil
        )
        var values = catalog(records: records)
        let sourceValue = values.removeValue(forKey: sourceScope)
        let sourceNames = sourceValue ?? []
        let changes = prepareQuantityTypeRecordChanges(
            from: sourceModule, to: destinationModule, records: records
        )
        let movedNames = changes.flatMap { change in
            return LibraryMistakeTagPolicy.references(from: change.record.jsonObject ?? [:])
                .filter { $0.module == sourceModule && $0.typeID == nil }
                .map(\.name)
        }
        let mergedNames = uniqueNames((values[destinationScope] ?? []) + sourceNames + movedNames)
        if mergedNames.isEmpty {
            values.removeValue(forKey: destinationScope)
        } else {
            values[destinationScope] = mergedNames
        }

        if sourceValue != nil || !changes.isEmpty {
            try persist(values, records: records, context: context, save: false)
        }
        for change in changes {
            change.record.replacePayload(change.afterPayload, indexPayload: change.afterIndexPayload)
            change.record.updatedAt = change.updatedAt
        }
    }

    static func add(
        _ rawName: String,
        subject: String,
        module: String,
        typeID: String?,
        groupID: String? = nil,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let name = normalized(rawName)
        guard !name.isEmpty else { throw LibraryMistakeTagRepositoryError.emptyName }
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        guard !(values[scope] ?? []).contains(name) else {
            throw LibraryMistakeTagRepositoryError.duplicateName
        }
        values[scope, default: []].append(name)

        guard let groupID else {
            try persist(values, records: records, context: context)
            return
        }

        let catalogRecord = keyValueRecord(records: records)
        let catalogSnapshot = snapshot(catalogRecord)
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let groupSnapshot = snapshot(groupRecord)
        do {
            try context.transaction {
                try persist(values, records: records, context: context, save: false)
                try LibraryKnowledgePointGroupRepository.addTagToGroup(
                    name, groupID: groupID, subject: subject, module: module, typeID: typeID,
                    category: .mistakeTag, records: records, context: context, save: false
                )
            }
        } catch {
            restoreKeyValueRecord(catalogRecord, snapshot: catalogSnapshot, context: context)
            restoreKeyValueRecord(groupRecord, snapshot: groupSnapshot, context: context)
            throw error
        }
    }

    static func move(
        _ name: String,
        direction: Int,
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        guard var entries = values[scope], let index = entries.firstIndex(of: name) else { return }
        let destination = index + direction
        guard entries.indices.contains(destination) else { return }
        entries.swapAt(index, destination)
        values[scope] = entries
        try persist(values, records: records, context: context)
    }

    static func reorder(
        _ names: [String],
        subject: String,
        module: String,
        typeID: String?,
        groupID: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        let current = values[scope] ?? []
        let merged = LibraryKnowledgePointGroupRepository.mergedOrder(
            displayedOrder: names,
            groupID: groupID,
            fullOrder: current,
            subject: subject,
            module: module,
            typeID: typeID,
            category: .mistakeTag,
            records: records
        )
        guard merged.count == current.count, Set(merged) == Set(current), merged != current else { return }
        values[scope] = merged
        try persist(values, records: records, context: context)
    }

    @discardableResult
    static func rename(
        _ oldName: String,
        to rawNewName: String,
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        let newName = normalized(rawNewName)
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        let current = values[scope] ?? []
        guard !newName.isEmpty, newName != oldName, current.contains(oldName) else {
            return result(subject: subject, module: module, typeID: typeID, oldName: oldName, newName: newName, changes: [])
        }
        guard !current.contains(newName) else { throw LibraryMistakeTagRepositoryError.duplicateName }
        values[scope] = current.map { $0 == oldName ? newName : $0 }
        let source = LibraryKnowledgePointReference(module: module, typeID: typeID, name: oldName)
        let destination = LibraryKnowledgePointReference(module: module, typeID: typeID, name: newName)
        let changes = try prepareRecordChanges(
            subject: subject, source: source, destination: destination, records: records
        )
        try commit(
            values, changes: changes, records: records, context: context
        ) {
            try LibraryKnowledgePointGroupRepository.renameTagMember(
                oldName, to: newName, subject: subject, module: module, typeID: typeID,
                category: .mistakeTag, records: records, context: context, save: false
            )
        }
        return result(subject: subject, module: module, typeID: typeID, oldName: oldName, newName: newName, changes: changes)
    }

    @discardableResult
    static func delete(
        _ name: String,
        subject: String,
        module: String,
        typeID: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        let scope = LibraryMistakeTagPolicy.scopeKey(subject: subject, module: module, typeID: typeID)
        var values = catalog(records: records)
        let current = values[scope] ?? []
        guard current.contains(name) else {
            return result(subject: subject, module: module, typeID: typeID, oldName: name, newName: nil, changes: [])
        }
        values[scope] = current.filter { $0 != name }
        let source = LibraryKnowledgePointReference(module: module, typeID: typeID, name: name)
        let changes = try prepareRecordChanges(subject: subject, source: source, destination: nil, records: records)
        try commit(
            values, changes: changes, records: records, context: context
        ) {
            try LibraryKnowledgePointGroupRepository.renameTagMember(
                name, to: nil, subject: subject, module: module, typeID: typeID,
                category: .mistakeTag, records: records, context: context, save: false
            )
        }
        return result(subject: subject, module: module, typeID: typeID, oldName: name, newName: nil, changes: changes)
    }

    @discardableResult
    static func move(
        _ name: String,
        subject: String,
        from source: LibraryKnowledgePointReference,
        to destination: LibraryKnowledgePointReference,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        guard source != destination else { throw LibraryMistakeTagRepositoryError.sameScope }
        let sourceScope = LibraryMistakeTagPolicy.scopeKey(
            subject: subject, module: source.module ?? "", typeID: source.typeID
        )
        let destinationScope = LibraryMistakeTagPolicy.scopeKey(
            subject: subject, module: destination.module ?? "", typeID: destination.typeID
        )
        var values = catalog(records: records)
        guard let sourceNames = values[sourceScope], sourceNames.contains(name) else {
            throw LibraryMistakeTagRepositoryError.stale
        }
        values[sourceScope] = sourceNames.filter { $0 != name }
        if !(values[destinationScope] ?? []).contains(name) {
            values[destinationScope, default: []].append(name)
        }
        let sourceReference = LibraryKnowledgePointReference(
            module: source.module, typeID: source.typeID, name: name
        )
        let destinationReference = LibraryKnowledgePointReference(
            module: destination.module, typeID: destination.typeID, name: name
        )
        let changes = try prepareRecordChanges(
            subject: subject, source: sourceReference, destination: destinationReference, records: records
        )
        try commit(values, changes: changes, records: records, context: context) {
            try LibraryKnowledgePointGroupRepository.renameTagMember(
                name, to: nil, subject: subject, module: source.module ?? "", typeID: source.typeID,
                category: .mistakeTag, records: records, context: context, save: false
            )
        }
        return result(
            subject: subject,
            module: source.module ?? "",
            typeID: source.typeID,
            oldName: name,
            newName: name,
            changes: changes,
            destinationModule: destination.module,
            destinationTypeID: destination.typeID
        )
    }

    private static func catalog(records: [StoredRecord]) -> [String: [String]] {
        guard let object = keyValueRecord(records: records)?.jsonObject,
              let value = object["value"] as? [String: Any] else { return [:] }
        return value.reduce(into: [:]) { result, entry in
            guard let names = entry.value as? [String] else { return }
            var seen = Set<String>()
            result[entry.key] = names.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
        }
    }

    private static func persist(
        _ values: [String: [String]],
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        let object: [String: Any] = ["key": recordID, "value": values]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let existing = keyValueRecord(records: records)
        let before = snapshot(existing)
        do {
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = .now
            } else {
                context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
            }
            if shouldSave { try context.save() }
        } catch {
            restoreKeyValueRecord(existing, snapshot: before, context: context)
            throw error
        }
    }

    private static func prepareRecordChanges(
        subject: String,
        source: LibraryKnowledgePointReference,
        destination: LibraryKnowledgePointReference?,
        records: [StoredRecord]
    ) throws -> [PendingRecordChange] {
        var changes: [PendingRecordChange] = []
        for record in records where record.collection == "errors" {
            guard var object = record.jsonObject else { continue }
            let recordSubject = nonEmpty(object["subject"] as? String)
                ?? nonEmpty(record.subject)
                ?? nonEmpty(record.indexObject?["subject"] as? String)
            let recordModule = nonEmpty(object["module"] as? String)
                ?? nonEmpty(record.module)
                ?? nonEmpty(record.indexObject?["module"] as? String)
            guard recordSubject == subject, recordModule == source.module else { continue }
            let references = LibraryMistakeTagPolicy.references(from: object)
            guard references.contains(source) else { continue }
            let updated = LibraryMistakeTagPolicy.replacing(references, from: source, to: destination)
            guard updated != references else { continue }
            object["mistakeTagRefs"] = updated.map(\.jsonValue)
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            changes.append(PendingRecordChange(
                record: record,
                beforePayload: record.payload,
                beforeIndexPayload: record.indexPayload,
                beforeUpdatedAt: record.updatedAt,
                afterPayload: payload,
                afterIndexPayload: StoredRecord.makeIndexPayload(from: payload, collection: record.collection),
                updatedAt: .now
            ))
        }
        return changes
    }

    private static func prepareQuantityTypeRecordChanges(
        from sourceModule: String,
        to destinationModule: String,
        records: [StoredRecord]
    ) -> [PendingRecordChange] {
        var changes: [PendingRecordChange] = []
        for record in records where record.collection == "errors" {
            guard var object = record.jsonObject else { continue }
            let recordSubject = nonEmpty(object["subject"] as? String)
                ?? nonEmpty(record.subject)
                ?? nonEmpty(record.indexObject?["subject"] as? String)
            let recordModule = nonEmpty(object["module"] as? String)
                ?? nonEmpty(record.module)
                ?? nonEmpty(record.indexObject?["module"] as? String)
            guard recordSubject == "数量关系", recordModule == sourceModule else { continue }

            let references = LibraryMistakeTagPolicy.references(from: object)
            let updated = references.map { reference in
                guard reference.module == sourceModule, reference.typeID == nil else { return reference }
                return LibraryKnowledgePointReference(
                    module: destinationModule.isEmpty ? nil : destinationModule,
                    typeID: nil,
                    name: reference.name
                )
            }
            guard updated != references else { continue }
            object["mistakeTagRefs"] = updated.map(\.jsonValue)
            guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            changes.append(PendingRecordChange(
                record: record,
                beforePayload: record.payload,
                beforeIndexPayload: record.indexPayload,
                beforeUpdatedAt: record.updatedAt,
                afterPayload: payload,
                afterIndexPayload: StoredRecord.makeIndexPayload(from: payload, collection: record.collection),
                updatedAt: .now
            ))
        }
        return changes
    }

    private static func commit(
        _ values: [String: [String]],
        changes: [PendingRecordChange],
        records: [StoredRecord],
        context: ModelContext,
        updateGroups: () throws -> Void
    ) throws {
        let catalogRecord = keyValueRecord(records: records)
        let catalogSnapshot = snapshot(catalogRecord)
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let groupSnapshot = snapshot(groupRecord)
        do {
            try context.transaction {
                try persist(values, records: records, context: context, save: false)
                try updateGroups()
                for change in changes {
                    change.record.replacePayload(change.afterPayload, indexPayload: change.afterIndexPayload)
                    change.record.updatedAt = change.updatedAt
                }
            }
        } catch {
            restoreKeyValueRecord(catalogRecord, snapshot: catalogSnapshot, context: context)
            restoreKeyValueRecord(groupRecord, snapshot: groupSnapshot, context: context)
            for change in changes {
                change.record.replacePayload(change.beforePayload, indexPayload: change.beforeIndexPayload)
                change.record.updatedAt = change.beforeUpdatedAt
            }
            throw error
        }
    }

    private static func result(
        subject: String,
        module: String,
        typeID: String?,
        oldName: String,
        newName: String?,
        changes: [PendingRecordChange],
        destinationModule: String? = nil,
        destinationTypeID: String? = nil
    ) -> LibraryTagMutationResult {
        var mutation = LibraryTagMutationResult(
            kind: .mistakeTag,
            module: module,
            oldName: oldName,
            newName: newName,
            recordChanges: changes.map {
                LibraryTagRecordPayloadChange(
                    collection: $0.record.collection,
                    recordID: $0.record.recordID,
                    beforePayload: $0.beforePayload,
                    afterPayload: $0.afterPayload
                )
            },
            typeID: typeID,
            subject: subject,
            destinationModule: destinationModule,
            destinationTypeID: destinationTypeID
        )
        return mutation
    }

    private static func keyValueRecord(records: [StoredRecord]) -> StoredRecord? {
        records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
    }

    private static func snapshot(_ record: StoredRecord?) -> (Data, Data?, Date?)? {
        record.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
    }

    private static func restoreKeyValueRecord(
        _ record: StoredRecord?,
        snapshot: (Data, Data?, Date?)?,
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

    private static func normalized(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func uniqueNames(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.map(normalized).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

private enum LibraryMistakeTagRepositoryError: LocalizedError {
    case emptyName
    case duplicateName
    case sameScope
    case stale

    var errorDescription: String? {
        switch self {
        case .emptyName: "标签名称不能为空。"
        case .duplicateName: "当前题型已存在同名错因标签。"
        case .sameScope: "目标题型与当前题型相同。"
        case .stale: "错因标签目录已变化，请重新打开后重试。"
        }
    }
}
