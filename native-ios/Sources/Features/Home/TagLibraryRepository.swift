import Foundation
import SwiftData

enum ManagedTagKind: String, CaseIterable, Identifiable {
    case knowledgePoint = "考点"
    case errorCause = "错因"
    case thinkingTrap = "思维误区"
    var id: String { rawValue }
    var recordID: String {
        switch self {
        case .knowledgePoint: "kp_library"
        case .errorCause: "kp_ec_library"
        case .thinkingTrap: "kp_trap_library"
        }
    }
}

struct LibraryTagRecordPayloadChange: Equatable {
    let collection: String
    let recordID: String
    let beforePayload: Data
    let afterPayload: Data
}

struct LibraryTagMutationResult: Equatable {
    let kind: ManagedTagKind
    let module: String
    let oldName: String
    let newName: String?
    let recordChanges: [LibraryTagRecordPayloadChange]
}

enum TagLibraryRepository {
    static func tags(kind: ManagedTagKind, module: String, records: [StoredRecord]) -> [String] {
        let library = load(kind: kind, records: records)
        let values = library[module] ?? []
        return kind == .knowledgePoint ? KnowledgePointNameSorter.sorted(values) : values
    }

    static func add(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        try add([name], kind: kind, module: module, records: records, context: context)
    }

    static func add(
        _ names: [String], kind: ManagedTagKind, module: String,
        records: [StoredRecord], context: ModelContext, persist: Bool = true
    ) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        let values = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return }
        var changed = false
        for value in values where !(library[module] ?? []).contains(value) {
            library[module, default: []].append(value)
            changed = true
        }
        guard changed else { return }
        try save(library, kind: kind, records: records, context: context, persist: persist)
    }

    static func move(_ name: String, direction: Int, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        guard kind != .knowledgePoint else { return }
        var library = loadWithDefaults(kind: kind, records: records)
        guard var values = library[module], let index = values.firstIndex(of: name) else { return }
        let destination = index + direction
        guard values.indices.contains(destination) else { return }
        values.swapAt(index, destination)
        library[module] = values
        try save(library, kind: kind, records: records, context: context)
    }

    @discardableResult
    static func rename(_ oldName: String, to newName: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws -> LibraryTagMutationResult {
        var library = loadWithDefaults(kind: kind, records: records)
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != oldName, !(library[module] ?? []).contains(value) else {
            return LibraryTagMutationResult(kind: kind, module: module, oldName: oldName, newName: value, recordChanges: [])
        }
        library[module] = (library[module] ?? []).map { $0 == oldName ? value : $0 }
        return try mutate(
            library,
            oldName: oldName,
            newName: value,
            kind: kind,
            module: module,
            records: records,
            context: context
        )
    }

    @discardableResult
    static func delete(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws -> LibraryTagMutationResult {
        var library = loadWithDefaults(kind: kind, records: records)
        library[module] = (library[module] ?? []).filter { $0 != name }
        return try mutate(
            library,
            oldName: name,
            newName: nil,
            kind: kind,
            module: module,
            records: records,
            context: context
        )
    }

    private struct PendingRecordChange {
        let record: StoredRecord
        let beforePayload: Data
        let beforeIndexPayload: Data?
        let beforeUpdatedAt: Date?
        let afterPayload: Data
        let afterIndexPayload: Data?
        let updatedAt: Date
    }

    private static func mutate(
        _ library: [String: [String]],
        oldName: String,
        newName: String?,
        kind: ManagedTagKind,
        module: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryTagMutationResult {
        let changes = try prepareReferenceChanges(
            oldName: oldName,
            newName: newName,
            kind: kind,
            module: module,
            records: records
        )
        let existingLibraryRecord = records.first {
            $0.collection == "keyvalue" && $0.recordID == kind.recordID
        }
        let librarySnapshot = existingLibraryRecord.map {
            (payload: $0.payload, indexPayload: $0.indexPayload, updatedAt: $0.updatedAt)
        }

        do {
            try context.transaction {
                try save(library, kind: kind, records: records, context: context, persist: false)
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
            if let existingLibraryRecord, let librarySnapshot {
                existingLibraryRecord.replacePayload(librarySnapshot.payload, indexPayload: librarySnapshot.indexPayload)
                existingLibraryRecord.updatedAt = librarySnapshot.updatedAt
            } else if existingLibraryRecord == nil {
                let recordID = kind.recordID
                let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                    $0.collection == "keyvalue" && $0.recordID == recordID
                })
                for inserted in (try? context.fetch(descriptor)) ?? [] { context.delete(inserted) }
            }
            throw error
        }

        return LibraryTagMutationResult(
            kind: kind,
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
            }
        )
    }

    private static func loadWithDefaults(kind: ManagedTagKind, records: [StoredRecord]) -> [String: [String]] {
        load(kind: kind, records: records)
    }

    private static func load(kind: ManagedTagKind, records: [StoredRecord]) -> [String: [String]] {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == kind.recordID })?.jsonObject,
            let raw = object["value"] as? [String: Any]
        else { return [:] }
        return raw.reduce(into: [:]) { result, entry in
            result[entry.key] = (entry.value as? [String]) ?? (entry.value as? [Any])?.compactMap { $0 as? String } ?? []
        }
    }

    private static func save(
        _ library: [String: [String]], kind: ManagedTagKind,
        records: [StoredRecord], context: ModelContext, persist: Bool = true
    ) throws {
        let object: [String: Any] = ["key": kind.recordID, "value": library]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == kind.recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: kind.recordID, payload: payload, updatedAt: .now))
        }
        if persist { try context.save() }
    }

    private static func prepareReferenceChanges(
        oldName: String,
        newName: String?,
        kind: ManagedTagKind,
        module: String,
        records: [StoredRecord]
    ) throws -> [PendingRecordChange] {
        let mutationDate = Date.now
        var changes: [PendingRecordChange] = []
        for record in records where (record.collection == "errors" || record.collection == "notes") {
            let matchesModule = record.module == module
                || (kind == .thinkingTrap && module == "数量关系-弱项" && record.subject == "数量关系")
            guard matchesModule else { continue }
            guard var object = record.jsonObject else { continue }
            var changed = false
            if kind == .knowledgePoint {
                if var values = object["knowledgePoints"] as? [String], values.contains(oldName) {
                    values = replacing(oldName, with: newName, in: values)
                    object["knowledgePoints"] = values
                    changed = true
                }
                if let value = object["knowledgePoint"] as? String,
                   let updated = replacing(oldName, with: newName, in: value, separator: "、") {
                    object["knowledgePoint"] = updated
                    changed = true
                }
            } else if kind == .errorCause {
                if record.subject == "数量关系" {
                    let values = LibraryQuantityErrorCauseCompatibility.values(
                        errorCause: object["errorCause"],
                        weaknessTags: nil,
                        authoritative: true
                    )
                    if values.contains(oldName) {
                        let updatedValues = replacing(oldName, with: newName, in: values)
                        object["errorCause"] = updatedValues
                        LibraryQuantityErrorCauseCompatibility.markAuthoritative(in: &object)
                        changed = true
                    }
                } else if record.subject == "资料分析" {
                    let lines = LibraryDataAnalysisCauseLayout.splitLines(object["errorCause"])
                    if lines.contains(oldName) {
                        object["errorCause"] = replacing(oldName, with: newName, in: lines).joined(separator: "\n")
                        changed = true
                    }
                } else if let value = object["errorCause"] as? String,
                          let updated = replacing(oldName, with: newName, in: value, separator: "、") {
                    object["errorCause"] = updated
                    changed = true
                }
            } else if kind == .thinkingTrap, module == "数量关系-弱项" {
                if var values = object["weaknessTags"] as? [String], values.contains(oldName) {
                    values = replacing(oldName, with: newName, in: values)
                    object["weaknessTags"] = values
                    changed = true
                }
            } else if kind == .thinkingTrap, object["pitfall"] as? String == oldName {
                object["pitfall"] = newName ?? ""
                changed = true
            }
            if changed {
                let afterPayload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                changes.append(PendingRecordChange(
                    record: record,
                    beforePayload: record.payload,
                    beforeIndexPayload: record.indexPayload,
                    beforeUpdatedAt: record.updatedAt,
                    afterPayload: afterPayload,
                    afterIndexPayload: StoredRecord.makeIndexPayload(from: afterPayload, collection: record.collection),
                    updatedAt: mutationDate
                ))
            }
        }
        return changes
    }

    private static func replacing(_ oldName: String, with newName: String?, in values: [String]) -> [String] {
        values.compactMap { value in value == oldName ? newName : value }
    }

    private static func replacing(_ oldName: String, with newName: String?, in value: String, separator: String) -> String? {
        let values = value.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
        guard values.contains(oldName) else { return nil }
        return replacing(oldName, with: newName, in: values).joined(separator: separator)
    }

}
