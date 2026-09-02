import Foundation
import SwiftData

struct NoteTypeDefinition: Codable, Identifiable, Equatable {
    var name: String
    var color: String
    var enabled: Bool
    var id: String { name }
}

enum NoteTypeRepository {
    static let colors = ["#0066CC", "#FF9500", "#34C759", "#9B7BFF", "#FF3B30", "#00A6A6"]
    private static let recordID = "legacy.noteTypes"
    private static let defaults = [
        NoteTypeDefinition(name: "技巧总结", color: "#0066CC", enabled: true),
        NoteTypeDefinition(name: "解题方法", color: "#FF9500", enabled: true),
        NoteTypeDefinition(name: "知识积累", color: "#34C759", enabled: true),
        NoteTypeDefinition(name: "错题复盘", color: "#9B7BFF", enabled: true)
    ]

    static func types(subject: String, module: String, records: [StoredRecord], includeDisabled: Bool = false) -> [NoteTypeDefinition] {
        let storage = read(records: records)
        let key = contextKey(subject: subject, module: module)
        let values = storage.contexts[key] ?? storage.legacy
        return includeDisabled ? values : values.filter(\.enabled)
    }

    static func add(_ name: String, color: String, subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        var values = types(subject: subject, module: module, records: records, includeDisabled: true)
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, !values.contains(where: { $0.name == clean }) else { return }
        values.append(.init(name: clean, color: color, enabled: true))
        try save(values, subject: subject, module: module, records: records, context: context)
    }

    static func rename(_ oldName: String, to newName: String, color: String, subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        var values = types(subject: subject, module: module, records: records, includeDisabled: true)
        let clean = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = values.firstIndex(where: { $0.name == oldName }), !clean.isEmpty else { return }
        guard clean == oldName || !values.contains(where: { $0.name == clean }) else { return }
        values[index].name = clean
        values[index].color = color
        for record in matchingNotes(subject: subject, module: module, records: records) {
            var object = record.jsonObject ?? [:]
            guard object["type"] as? String == oldName else { continue }
            object["type"] = clean
            try update(record: record, object: object)
        }
        try save(values, subject: subject, module: module, records: records, context: context)
    }

    static func setEnabled(_ name: String, enabled: Bool, subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        var values = types(subject: subject, module: module, records: records, includeDisabled: true)
        guard let index = values.firstIndex(where: { $0.name == name }) else { return }
        values[index].enabled = enabled
        try save(values, subject: subject, module: module, records: records, context: context)
    }

    static func move(_ name: String, offset: Int, subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        var values = types(subject: subject, module: module, records: records, includeDisabled: true)
        guard let index = values.firstIndex(where: { $0.name == name }) else { return }
        let target = index + offset
        guard values.indices.contains(target) else { return }
        values.swapAt(index, target)
        try save(values, subject: subject, module: module, records: records, context: context)
    }

    static func delete(_ name: String, subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        let values = types(subject: subject, module: module, records: records, includeDisabled: true).filter { $0.name != name }
        for record in matchingNotes(subject: subject, module: module, records: records) {
            var object = record.jsonObject ?? [:]
            guard object["type"] as? String == name else { continue }
            object["type"] = ""
            try update(record: record, object: object)
        }
        try save(values, subject: subject, module: module, records: records, context: context)
    }

    static func color(for name: String, subject: String, module: String, records: [StoredRecord]) -> String {
        types(subject: subject, module: module, records: records, includeDisabled: true).first { $0.name == name }?.color ?? "#0066CC"
    }

    private struct Storage {
        var legacy: [NoteTypeDefinition]
        var contexts: [String: [NoteTypeDefinition]]
    }

    private static func read(records: [StoredRecord]) -> Storage {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID })?.jsonObject,
            let value = object["value"] as? [String: Any]
        else { return Storage(legacy: defaults, contexts: [:]) }
        let legacy = decode(value["legacy"]) ?? defaults
        var contexts: [String: [NoteTypeDefinition]] = [:]
        if let raw = value["contexts"] as? [String: Any] {
            for (key, item) in raw { contexts[key] = decode(item) ?? [] }
        }
        return Storage(legacy: legacy.isEmpty ? defaults : legacy, contexts: contexts)
    }

    private static func decode(_ value: Any?) -> [NoteTypeDefinition]? {
        guard let value, JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode([NoteTypeDefinition].self, from: data)
    }

    private static func save(_ values: [NoteTypeDefinition], subject: String, module: String, records: [StoredRecord], context: ModelContext) throws {
        var storage = read(records: records)
        storage.contexts[contextKey(subject: subject, module: module)] = values
        let encoder = JSONEncoder()
        let legacyObject = try JSONSerialization.jsonObject(with: encoder.encode(storage.legacy))
        var contextsObject: [String: Any] = [:]
        for (key, list) in storage.contexts { contextsObject[key] = try JSONSerialization.jsonObject(with: encoder.encode(list)) }
        let object: [String: Any] = ["key": recordID, "value": ["legacy": legacyObject, "contexts": contextsObject]]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
        }
        try context.save()
    }

    private static func matchingNotes(subject: String, module: String, records: [StoredRecord]) -> [StoredRecord] {
        records.filter { $0.collection == "notes" && $0.subject == subject && ($0.module ?? "") == module }
    }

    private static func update(record: StoredRecord, object: [String: Any]) throws {
        record.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
        record.updatedAt = .now
    }

    private static func contextKey(subject: String, module: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: [subject, module], options: [])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "[\"\(subject)\",\"\(module)\"]"
    }
}
