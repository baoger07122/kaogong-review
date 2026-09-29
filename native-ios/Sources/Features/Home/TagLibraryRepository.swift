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

enum TagLibraryRepository {
    static func tags(kind: ManagedTagKind, module: String, records: [StoredRecord]) -> [String] {
        let library = load(kind: kind, records: records)
        return library[module] ?? []
    }

    static func add(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        try add([name], kind: kind, module: module, records: records, context: context)
    }

    static func add(_ names: [String], kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        let values = names
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !values.isEmpty else { return }
        for value in values where !(library[module] ?? []).contains(value) {
            library[module, default: []].append(value)
        }
        try save(library, kind: kind, records: records, context: context)
    }

    static func move(_ name: String, direction: Int, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        guard var values = library[module], let index = values.firstIndex(of: name) else { return }
        let destination = index + direction
        guard values.indices.contains(destination) else { return }
        values.swapAt(index, destination)
        library[module] = values
        try save(library, kind: kind, records: records, context: context)
    }

    static func rename(_ oldName: String, to newName: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != oldName, !(library[module] ?? []).contains(value) else { return }
        library[module] = (library[module] ?? []).map { $0 == oldName ? value : $0 }
        try save(library, kind: kind, records: records, context: context)
        try updateReferences(oldName: oldName, newName: value, kind: kind, module: module, records: records, context: context)
    }

    static func delete(_ name: String, kind: ManagedTagKind, module: String, records: [StoredRecord], context: ModelContext) throws {
        var library = loadWithDefaults(kind: kind, records: records)
        library[module] = (library[module] ?? []).filter { $0 != name }
        try save(library, kind: kind, records: records, context: context)
        try updateReferences(oldName: name, newName: nil, kind: kind, module: module, records: records, context: context)
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

    private static func save(_ library: [String: [String]], kind: ManagedTagKind, records: [StoredRecord], context: ModelContext) throws {
        let object: [String: Any] = ["key": kind.recordID, "value": library]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == kind.recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: kind.recordID, payload: payload, updatedAt: .now))
        }
        try context.save()
    }

    private static func updateReferences(
        oldName: String,
        newName: String?,
        kind: ManagedTagKind,
        module: String,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        for record in records where (record.collection == "errors" || record.collection == "notes") {
            let matchesModule = record.module == module
                || (kind == .thinkingTrap && module == "数量关系-弱项" && record.subject == "数量关系")
            guard matchesModule else { continue }
            guard var object = record.jsonObject else { continue }
            var changed = false
            if kind == .knowledgePoint {
                if var values = object["knowledgePoints"] as? [String], values.contains(oldName) {
                    values = values.compactMap { $0 == oldName ? newName : $0 }
                    object["knowledgePoints"] = values
                    changed = true
                }
                if object["knowledgePoint"] as? String == oldName {
                    object["knowledgePoint"] = newName ?? ""
                    changed = true
                }
            } else if kind == .errorCause, object["errorCause"] as? String == oldName {
                object["errorCause"] = newName ?? ""
                changed = true
            } else if kind == .thinkingTrap {
                if module == "数量关系-弱项", var values = object["weaknessTags"] as? [String], values.contains(oldName) {
                    values = values.compactMap { $0 == oldName ? newName : $0 }
                    object["weaknessTags"] = values
                    changed = true
                } else if object["pitfall"] as? String == oldName {
                    object["pitfall"] = newName ?? ""
                    changed = true
                }
            }
            if changed {
                record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                record.updatedAt = .now
            }
        }
        try context.save()
    }

}
