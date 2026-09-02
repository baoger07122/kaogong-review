import Foundation
import SwiftData

@Model
final class StoredRecord {
    @Attribute(.unique) var compoundID: String
    var collection: String
    var recordID: String
    var payload: Data
    var indexPayload: Data?
    var subject: String?
    var module: String?
    var createdAt: Date?
    var updatedAt: Date?

    init(
        collection: String,
        recordID: String,
        payload: Data,
        subject: String? = nil,
        module: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil
    ) {
        self.compoundID = "\(collection):\(recordID)"
        self.collection = collection
        self.recordID = recordID
        self.payload = payload
        self.indexPayload = Self.makeIndexPayload(from: payload, collection: collection)
        self.subject = subject
        self.module = module
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var jsonObject: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    }

    var indexObject: [String: Any]? {
        guard let indexPayload else { return jsonObject }
        return (try? JSONSerialization.jsonObject(with: indexPayload)) as? [String: Any]
    }

    func replacePayload(_ value: Data) {
        payload = value
        indexPayload = Self.makeIndexPayload(from: value, collection: collection)
    }

    var title: String {
        let object = indexObject
        return (object?["title"] as? String)
            ?? (object?["question"] as? String)
            ?? (object?["name"] as? String)
            ?? (object?["text"] as? String)
            ?? "未命名记录"
    }

    private static func makeIndexPayload(from payload: Data, collection: String) -> Data? {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let keys: Set<String>
        switch collection {
        case "errors":
            keys = [
                "id", "subject", "module", "knowledgePoints", "knowledgePoint", "errorCause", "status",
                "question", "title", "type", "category", "createdAt", "updatedAt", "lastReviewDate",
                "questionSource", "sourceYear", "sourceExamType", "sourceRegion",
                "accuracy", "reviewCount", "sourceExamId"
            ]
        case "notes":
            keys = ["id", "subject", "module", "title", "content", "type", "category", "createdAt", "updatedAt"]
        case "stickies":
            keys = ["id", "subject", "module", "content", "tag", "color", "colorHex", "pinned", "createdAt", "updatedAt"]
        case "words":
            keys = [
                "id", "subject", "module", "title", "name", "words", "type", "category", "meaning", "pinyin",
                "sentiment", "example", "compareNote", "myUnderstanding", "collocations", "pos", "compareWords",
                "createdAt", "updatedAt"
            ]
        default:
            keys = Set(object.keys).subtracting([
                "image", "images", "screenDoodle", "handNote", "pencilKitData", "legacyDrawingPreview",
                "drawingPreview", "doodle"
            ])
        }
        let index = object.filter { keys.contains($0.key) }
        return try? JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    }
}
