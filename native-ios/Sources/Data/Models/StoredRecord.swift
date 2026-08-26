import Foundation
import SwiftData

@Model
final class StoredRecord {
    @Attribute(.unique) var compoundID: String
    var collection: String
    var recordID: String
    var payload: Data
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
        self.subject = subject
        self.module = module
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var jsonObject: [String: Any]? {
        (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
    }

    var title: String {
        let object = jsonObject
        return (object?["title"] as? String)
            ?? (object?["question"] as? String)
            ?? (object?["name"] as? String)
            ?? (object?["text"] as? String)
            ?? "未命名记录"
    }
}

