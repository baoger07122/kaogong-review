import Foundation
import SwiftData

enum QuantityQuestionTypeRepository {
    private static let recordID = "quantity_question_types"

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
        values[index] = value
        try updateRecordModules(from: oldName, to: value, records: records)
        try renameTagLibraryKeys(from: oldName, to: value, records: records)
        try save(values, records: records, context: context)
    }

    static func delete(_ name: String, records: [StoredRecord], context: ModelContext) throws {
        let values = types(records: records).filter { $0 != name }
        try updateRecordModules(from: name, to: "", records: records)
        try renameTagLibraryKeys(from: name, to: nil, records: records)
        try save(values, records: records, context: context)
    }

    private static func storedTypes(records: [StoredRecord]) -> [String] {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID })?.jsonObject,
            let values = object["value"] as? [String]
        else { return [] }
        return orderedUnique(values.map(clean).filter { !$0.isEmpty })
    }

    private static func save(_ values: [String], records: [StoredRecord], context: ModelContext) throws {
        let object: [String: Any] = ["key": recordID, "value": orderedUnique(values)]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
        }
        try context.save()
    }

    private static func updateRecordModules(from oldName: String, to newName: String, records: [StoredRecord]) throws {
        for record in records where record.subject == "数量关系" && record.module == oldName {
            guard var object = record.jsonObject else { continue }
            object["module"] = newName
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
        }
    }

    private static func renameTagLibraryKeys(from oldName: String, to newName: String?, records: [StoredRecord]) throws {
        for recordID in ManagedTagKind.allCases.map(\.recordID) {
            guard
                let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }),
                var object = record.jsonObject,
                var library = object["value"] as? [String: Any],
                let values = library.removeValue(forKey: oldName)
            else { continue }
            if let newName, library[newName] == nil { library[newName] = values }
            object["value"] = library
            record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            record.updatedAt = .now
        }
    }

    private static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func orderedUnique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
