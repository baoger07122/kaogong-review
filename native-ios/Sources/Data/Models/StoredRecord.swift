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
    @Transient private var cachedCompatibilityFields: [String: Any]? = nil

    init(
        collection: String,
        recordID: String,
        payload: Data,
        subject: String? = nil,
        module: String? = nil,
        createdAt: Date? = nil,
        updatedAt: Date? = nil,
        precomputedIndexPayload: Data? = nil
    ) {
        self.compoundID = "\(collection):\(recordID)"
        self.collection = collection
        self.recordID = recordID
        self.payload = payload
        self.indexPayload = precomputedIndexPayload ?? Self.makeIndexPayload(from: payload, collection: collection)
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

    var compatibilityIndexObject: [String: Any]? {
        guard var indexed = indexObject else { return indexObject }
        let fields: [String]
        switch collection {
        case "errors":
            fields = ["errorCause", "cause", "reason", "compareGroups"]
        case "words":
            fields = ["linkedErrors", "relatedErrorIds"]
        default:
            return indexed
        }
        let missing = fields.filter { indexed[$0] == nil }
        guard !missing.isEmpty else { return indexed }
        if cachedCompatibilityFields == nil {
            let source = jsonObject ?? [:]
            cachedCompatibilityFields = source.filter { fields.contains($0.key) }
        }
        for key in missing {
            if let value = cachedCompatibilityFields?[key] { indexed[key] = value }
        }
        return indexed
    }

    var reviewSourceMetadata: [String: Any] {
        var value = indexObject ?? [:]
        for (key, item) in ReviewSourceMetadataCache.shared.fields(for: compoundID, payload: payload)
            where value[key] == nil || value[key] is NSNull {
            value[key] = item
        }
        return value
    }

    var isShenlunRecord: Bool {
        if subject?.trimmingCharacters(in: .whitespacesAndNewlines) == "申论" { return true }
        let object = indexObject
        if (object?["subject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) == "申论"
            || (object?["isShenlun"] as? Bool) == true {
            return true
        }
        let indexedSubject = (object?["subject"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (subject?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true),
              indexedSubject?.isEmpty ?? true else { return false }
        return (jsonObject?["isShenlun"] as? Bool) == true
    }

    var shenlunFormatVersion: Int? {
        guard let value = jsonObject?["shenlunFormatVersion"] else { return nil }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    var requiresShenlunAdaptation: Bool {
        guard isShenlunRecord else { return false }
        guard let version = shenlunFormatVersion else { return true }
        return version < ShenlunRecordFormat.currentVersion
    }

    func replacePayload(_ value: Data) {
        replacePayload(value, indexPayload: Self.makeIndexPayload(from: value, collection: collection))
    }

    func replacePayload(_ value: Data, indexPayload: Data?) {
        payload = value
        self.indexPayload = indexPayload
        cachedCompatibilityFields = nil
    }

    var title: String {
        let object = indexObject
        return (object?["title"] as? String)
            ?? (object?["question"] as? String)
            ?? (object?["name"] as? String)
            ?? (object?["text"] as? String)
            ?? "未命名记录"
    }

    static func makeIndexPayload(from payload: Data, collection: String) -> Data? {
        guard let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any] else { return nil }
        let keys: Set<String>
        switch collection {
        case "errors":
            keys = [
                "id", "subject", "module", "knowledgePoints", "knowledgePoint", "knowledgePointRefs", "errorCause", "errorTypeID", "status",
                "cause", "reason", "compareGroups",
                "question", "title", "type", "category", "isShenlun", "createdAt", "updatedAt", "lastReviewDate",
                "questionSource", "source", "questionNumber", "sourceYear", "sourceExamType", "sourceRegion",
                "accuracy", "reviewCount", "sourceExamId", "pitfall", "reminder", "linkedWordIds", "options",
                "dataAnalysisMaterialText",
                "imageDisplayMetadata", "imageCount", "optionImageIDs",
                "questionBankPaperID", "questionBankQuestionID",
                "shenlunFormatVersion",
                "quantityStructure", "weaknessTags", "isDifficult", "needsReview",
                "reviewSource", "examType", "paperType", "sourceType"
            ]
        case "notes":
            keys = [
                "id", "subject", "module", "title", "content", "type", "category", "createdAt", "updatedAt",
                "knowledgePoint", "knowledgePoints", "quantityStructure", "weaknessTags",
                "reviewSource", "examType", "paperType", "sourceType", "sourceExamId"
            ]
        case "stickies":
            keys = [
                "id", "subject", "module", "content", "tag", "color", "colorHex", "pinned", "createdAt", "updatedAt",
                "reviewSource", "examType", "paperType", "sourceType", "sourceExamId"
            ]
        case "words":
            keys = [
                "id", "subject", "module", "title", "name", "words", "type", "category", "meaning", "pinyin",
                "sentiment", "example", "compareNote", "myUnderstanding", "collocations", "pos", "compareWords",
                "judgmentHint", "commonMeaning", "entryKind", "createdAt", "updatedAt", "linkedErrors", "relatedErrorIds"
            ]
        default:
            keys = Set(object.keys).subtracting([
                "image", "images", "screenDoodle", "handNote", "pencilKitData", "legacyDrawingPreview",
                "drawingPreview", "doodle"
            ])
        }
        var index = object.filter { keys.contains($0.key) }
        if collection == "errors" {
            let images = object["images"] as? [String] ?? []
            let hasLegacyImage = (object["image"] as? String)?.isEmpty == false
            index["imageCount"] = images.isEmpty ? (hasLegacyImage ? 1 : 0) : images.count
        }
        return try? JSONSerialization.data(withJSONObject: index, options: [.sortedKeys])
    }
}
