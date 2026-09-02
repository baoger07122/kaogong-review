import Foundation
import SwiftData

enum SpeedRepository {
    private static let settingsKey = "native.speed.settings"
    private static let historyKey = "native.speed.history"
    private static let estimateKey = "native.speed.estimate"

    static func settings(from records: [StoredRecord]) -> SpeedSettings {
        decode(SpeedSettings.self, key: settingsKey, records: records) ?? SpeedSettings()
    }

    static func history(from records: [StoredRecord]) -> [SpeedRecord] {
        decode([SpeedRecord].self, key: historyKey, records: records) ?? []
    }

    static func estimateRows(from records: [StoredRecord]) -> [SpeedEstimateRow] {
        decode([SpeedEstimateRow].self, key: estimateKey, records: records) ?? [
            .init(id: UUID().uuidString, minimum: 101, maximum: 149, value: 100),
            .init(id: UUID().uuidString, minimum: 150, maximum: 179, value: 143),
            .init(id: UUID().uuidString, minimum: 180, maximum: 199, value: 188),
            .init(id: UUID().uuidString, minimum: 200, maximum: 249, value: 200),
            .init(id: UUID().uuidString, minimum: 250, maximum: 299, value: 250),
            .init(id: UUID().uuidString, minimum: 300, maximum: 399, value: 300),
            .init(id: UUID().uuidString, minimum: 400, maximum: 499, value: 400),
            .init(id: UUID().uuidString, minimum: 500, maximum: 599, value: 500)
        ]
    }

    static func save<T: Encodable>(_ value: T, key: String, records: [StoredRecord], context: ModelContext) throws {
        let encoded = try JSONEncoder.configured.encode(value)
        let foundation = try JSONSerialization.jsonObject(with: encoded)
        let object: [String: Any] = ["key": key, "value": foundation]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let record = records.first(where: { $0.collection == "keyvalue" && $0.recordID == key }) {
            record.replacePayload(payload)
            record.updatedAt = .now
        } else {
            context.insert(StoredRecord(collection: "keyvalue", recordID: key, payload: payload, updatedAt: .now))
        }
        try context.save()
    }

    static func saveSettings(_ value: SpeedSettings, records: [StoredRecord], context: ModelContext) throws {
        try save(value, key: settingsKey, records: records, context: context)
    }

    static func saveHistory(_ value: [SpeedRecord], records: [StoredRecord], context: ModelContext) throws {
        try save(value, key: historyKey, records: records, context: context)
    }

    static func saveEstimateRows(_ value: [SpeedEstimateRow], records: [StoredRecord], context: ModelContext) throws {
        try save(value, key: estimateKey, records: records, context: context)
    }

    private static func decode<T: Decodable>(_ type: T.Type, key: String, records: [StoredRecord]) -> T? {
        guard
            let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == key })?.jsonObject,
            let value = object["value"],
            JSONSerialization.isValidJSONObject(value),
            let data = try? JSONSerialization.data(withJSONObject: value)
        else { return nil }
        return try? JSONDecoder.configured.decode(type, from: data)
    }
}

private extension JSONEncoder {
    static var configured: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var configured: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
