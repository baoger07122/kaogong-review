import Foundation
import SwiftData

struct VerbalKnowledgePointMigrationReviewItem: Identifiable, Equatable {
    let recordID: String
    let title: String
    let summary: String

    var id: String { recordID }
}

struct VerbalKnowledgePointMigrationPreview: Equatable {
    let source: LibraryKnowledgePointReference
    let destination: LibraryKnowledgePointReference
    let sourceTitle: String
    let destinationTitle: String
    let destinationAlreadyExists: Bool
    let nameOnlyCandidates: [LibraryKnowledgePointReference]
    let reviewItems: [VerbalKnowledgePointMigrationReviewItem]
    let resolutionChoices: [LibraryKnowledgePointReference]
    let resolutionChoiceTitles: [String: String]
}

struct VerbalKnowledgePointMigrationResult: Equatable {
    let changedRecordCount: Int
    let retainedAssociationCount: Int
}

enum VerbalKnowledgePointMigrationError: LocalizedError {
    case stale
    case unresolved
    case sameType

    var errorDescription: String? {
        switch self {
        case .stale: return "考点目录或关联题目已变化，未写入任何修改。请重新打开题型选择后再试。"
        case .unresolved: return "仍有未核对的题目关联，请为每道题选择所属考点。"
        case .sameType: return "目标题型与当前题型相同。"
        }
    }
}

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

    static func migrationPreview(
        _ rawName: String,
        module: String,
        fromTypeID sourceTypeID: String?,
        toTypeID destinationTypeID: String,
        records: [StoredRecord]
    ) throws -> VerbalKnowledgePointMigrationPreview {
        let name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw VerbalKnowledgePointMigrationError.stale }
        let source = LibraryKnowledgePointReference(module: module, typeID: sourceTypeID, name: name)
        let destination = LibraryKnowledgePointReference(module: module, typeID: destinationTypeID, name: name)
        guard source != destination else { throw VerbalKnowledgePointMigrationError.sameType }

        let types = LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
        guard types.contains(where: { $0.module == module && $0.id == destinationTypeID }) else {
            throw VerbalKnowledgePointMigrationError.stale
        }
        let sourceNames = sourceTypeID.map {
            tags(module: module, typeID: $0, records: records)
        } ?? TagLibraryRepository.tags(kind: .knowledgePoint, module: module, records: records)
        guard sourceNames.contains(name) else { throw VerbalKnowledgePointMigrationError.stale }

        let destinationAlreadyExists = tags(module: module, typeID: destinationTypeID, records: records).contains(name)
        let candidates = nameOnlyCandidates(name: name, source: source, records: records)
        let reviewItems = records.compactMap { record -> VerbalKnowledgePointMigrationReviewItem? in
            guard record.collection == "errors",
                  (record.subject ?? record.indexObject?["subject"] as? String) == "言语理解",
                  let object = record.jsonObject else { return nil }
            let references = LibraryKnowledgePointReferencePolicy.references(from: object)
            let plan = VerbalLegacyKnowledgePointMigrationPolicy.plan(
                references: references, source: source, destination: destination,
                nameOnlyCandidates: candidates
            )
            guard plan.hasUnresolvedNameOnlyReference,
                  references.contains(where: { $0.module == nil && $0.typeID == nil && $0.name == name }) else { return nil }
            let summary = ["question", "content", "stem", "title"]
                .compactMap { object[$0] as? String }
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first { !$0.isEmpty } ?? record.title
            return VerbalKnowledgePointMigrationReviewItem(
                recordID: record.compoundID,
                title: record.title,
                summary: String(summary.prefix(120))
            )
        }
        let resolutionChoices = LibraryKnowledgePointReferencePolicy.uniqueReferences(
            candidates.filter { $0 != source } + [destination]
        )
        let resolutionChoiceTitles = Dictionary(uniqueKeysWithValues: resolutionChoices.map { reference in
            let title = "\(migrationReferenceTitle(reference, types: types)) · \(reference.name)"
            return (reference.id, title)
        })

        return VerbalKnowledgePointMigrationPreview(
            source: source,
            destination: destination,
            sourceTitle: migrationReferenceTitle(source, types: types),
            destinationTitle: migrationReferenceTitle(destination, types: types),
            destinationAlreadyExists: destinationAlreadyExists,
            nameOnlyCandidates: candidates,
            reviewItems: reviewItems,
            resolutionChoices: resolutionChoices,
            resolutionChoiceTitles: resolutionChoiceTitles
        )
    }

    static func moveKnowledgePoint(
        _ rawName: String,
        module: String,
        fromTypeID sourceTypeID: String?,
        toTypeID destinationTypeID: String,
        resolving ambiguousNameOnlyReferences: [String: LibraryKnowledgePointReference],
        records: [StoredRecord],
        context: ModelContext
    ) throws -> VerbalKnowledgePointMigrationResult {
        let preview = try migrationPreview(
            rawName, module: module, fromTypeID: sourceTypeID,
            toTypeID: destinationTypeID, records: records
        )
        guard preview.reviewItems.allSatisfy({ ambiguousNameOnlyReferences[$0.recordID] != nil }) else {
            throw VerbalKnowledgePointMigrationError.unresolved
        }
        guard preview.reviewItems.allSatisfy({ item in
            guard let choice = ambiguousNameOnlyReferences[item.recordID] else { return true }
            return preview.resolutionChoices.contains(choice)
        }) else {
            throw VerbalKnowledgePointMigrationError.stale
        }

        let name = preview.source.name
        let legacyRecordID = ManagedTagKind.knowledgePoint.recordID
        let legacyRecord = records.first { $0.collection == "keyvalue" && $0.recordID == legacyRecordID }
        var legacyValue = legacyRecord?.jsonObject?["value"] as? [String: Any] ?? [:]
        var legacyNames = legacyValue[module] as? [String] ?? []
        var typedGroups = loadGroups(records: records)
        var sourceTypedNames = sourceTypeID.map { typedGroups[module]?[$0] ?? [] } ?? []
        var destinationNames = typedGroups[module]?[destinationTypeID] ?? []
        if let sourceTypeID {
            guard sourceTypedNames.contains(name) else { throw VerbalKnowledgePointMigrationError.stale }
            sourceTypedNames.removeAll { $0 == name }
            typedGroups[module, default: [:]][sourceTypeID] = sourceTypedNames
        } else {
            guard legacyNames.contains(name) else { throw VerbalKnowledgePointMigrationError.stale }
            legacyNames.removeAll { $0 == name }
            if legacyNames.isEmpty { legacyValue.removeValue(forKey: module) }
            else { legacyValue[module] = legacyNames }
        }
        if !destinationNames.contains(name) {
            destinationNames.append(name)
            typedGroups[module, default: [:]][destinationTypeID] = destinationNames
        }

        let changes = try prepareMigrationReferenceChanges(
            preview: preview,
            resolutions: ambiguousNameOnlyReferences,
            records: records
        )
        let retainedCount = changes.reduce(into: 0) { count, change in
            guard let before = (try? JSONSerialization.jsonObject(with: change.beforePayload)) as? [String: Any],
                  let after = (try? JSONSerialization.jsonObject(with: change.afterPayload)) as? [String: Any] else { return }
            let beforeReferences = LibraryKnowledgePointReferencePolicy.references(from: before)
            let hadSourceAssociation = beforeReferences.contains {
                $0.module == preview.source.module
                    && $0.typeID == preview.source.typeID
                    && $0.name == preview.source.name
            } || beforeReferences.contains {
                $0.module == nil && $0.typeID == nil && $0.name == preview.source.name
            }
            guard hadSourceAssociation,
                  LibraryKnowledgePointReferencePolicy.references(from: after).contains(preview.destination) else { return }
            count += 1
        }

        let typedRecord = records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
        let groupRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == LibraryKnowledgePointGroupRepository.recordID
        }
        let legacySnapshot = legacyRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let typedSnapshot = typedRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        let groupSnapshot = groupRecord.map { ($0.payload, $0.indexPayload, $0.updatedAt) }

        do {
            try context.transaction {
                if sourceTypeID == nil {
                    try persistLegacy(legacyValue, record: legacyRecord, context: context, save: false)
                }
                try persist(typedGroups, records: records, context: context, save: false)
                try LibraryKnowledgePointGroupRepository.renameTagMember(
                    name, to: nil, subject: "言语理解", module: module, typeID: sourceTypeID,
                    records: records, context: context, save: false
                )
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

        return VerbalKnowledgePointMigrationResult(
            changedRecordCount: changes.count,
            retainedAssociationCount: retainedCount
        )
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

    private static func nameOnlyCandidates(
        name: String,
        source: LibraryKnowledgePointReference,
        records: [StoredRecord]
    ) -> [LibraryKnowledgePointReference] {
        var candidates: [LibraryKnowledgePointReference] = []
        let legacyValues = records.first {
            $0.collection == "keyvalue" && $0.recordID == ManagedTagKind.knowledgePoint.recordID
        }?.jsonObject?["value"] as? [String: [String]] ?? [:]
        for (module, names) in legacyValues where names.contains(name) {
            candidates.append(LibraryKnowledgePointReference(module: module, name: name))
        }
        for type in LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records) {
            guard let module = type.module else { continue }
            if tags(module: module, typeID: type.id, records: records).contains(name) {
                candidates.append(LibraryKnowledgePointReference(module: module, typeID: type.id, name: name))
            }
        }
        if !candidates.contains(source) { candidates.append(source) }
        return LibraryKnowledgePointReferencePolicy.uniqueReferences(candidates)
    }

    private static func migrationReferenceTitle(
        _ reference: LibraryKnowledgePointReference,
        types: [LibraryErrorType]
    ) -> String {
        guard let typeID = reference.typeID else {
            return "\(reference.module ?? "言语理解") · 旧考点"
        }
        let typeName = types.first(where: { $0.id == typeID && $0.module == reference.module })?.name ?? "题型已删除"
        return "\(reference.module ?? "言语理解") · \(typeName)"
    }

    private static func prepareMigrationReferenceChanges(
        preview: VerbalKnowledgePointMigrationPreview,
        resolutions: [String: LibraryKnowledgePointReference],
        records: [StoredRecord]
    ) throws -> [RecordChange] {
        var changes: [RecordChange] = []
        for record in records where record.collection == "errors"
            && (record.subject ?? record.indexObject?["subject"] as? String) == "言语理解" {
            guard var object = record.jsonObject else { continue }
            let references = LibraryKnowledgePointReferencePolicy.references(from: object)
            let resolution = resolutions[record.compoundID]
            let plan = VerbalLegacyKnowledgePointMigrationPolicy.plan(
                references: references,
                source: preview.source,
                destination: preview.destination,
                nameOnlyCandidates: preview.nameOnlyCandidates,
                nameOnlyResolution: resolution
            )
            guard !plan.hasUnresolvedNameOnlyReference else { throw VerbalKnowledgePointMigrationError.unresolved }
            guard plan.didChange else { continue }

            let displayNames = LibraryKnowledgePointReferencePolicy.displayNames(from: plan.references)
            object["knowledgePointRefs"] = plan.references.map(\.jsonValue)
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
        return changes
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
