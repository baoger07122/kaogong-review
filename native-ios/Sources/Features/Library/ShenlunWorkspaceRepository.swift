import Foundation
import SwiftData

enum ShenlunWorkspaceRepository {
    static let practiceCollection = "shenlun_workspace_practices"
    static let questionCollection = "shenlun_workspace_questions"
    static let materialCollection = "shenlun_workspace_materials"
    static let assetCollection = "shenlun_workspace_assets"
    static let answerCollection = "shenlun_workspace_answers"
    static let drawingCollection = "shenlun_workspace_drawings"

    private struct PendingPayload {
        var collection: String
        var id: String
        var payload: Data
        var createdAt: Date?
        var updatedAt: Date
    }

    static func practices(in context: ModelContext) throws -> [ShenlunWorkspacePractice] {
        try values(ShenlunWorkspacePractice.self, collection: practiceCollection, in: context)
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    static func practice(id: String, in context: ModelContext) throws -> ShenlunWorkspacePractice? {
        try value(ShenlunWorkspacePractice.self, id: id, collection: practiceCollection, in: context)
    }

    static func questions(practiceID: String, in context: ModelContext) throws -> [ShenlunWorkspaceQuestion] {
        try values(ShenlunWorkspaceQuestion.self, collection: questionCollection, in: context)
            .filter { $0.practiceID == practiceID }
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }

    static func question(id: String, in context: ModelContext) throws -> ShenlunWorkspaceQuestion? {
        try value(ShenlunWorkspaceQuestion.self, id: id, collection: questionCollection, in: context)
    }

    static func materials(practiceID: String, in context: ModelContext) throws -> [ShenlunWorkspaceMaterial] {
        try values(ShenlunWorkspaceMaterial.self, collection: materialCollection, in: context)
            .filter { $0.practiceID == practiceID }
            .sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }

    static func material(id: String, in context: ModelContext) throws -> ShenlunWorkspaceMaterial? {
        try value(ShenlunWorkspaceMaterial.self, id: id, collection: materialCollection, in: context)
    }

    static func asset(id: String, in context: ModelContext) throws -> ShenlunWorkspaceAsset? {
        try value(ShenlunWorkspaceAsset.self, id: id, collection: assetCollection, in: context)
    }

    static func answers(practiceID: String, in context: ModelContext) throws -> [String: ShenlunWorkspaceAnswer] {
        Dictionary(uniqueKeysWithValues: try values(ShenlunWorkspaceAnswer.self, collection: answerCollection, in: context)
            .filter { $0.practiceID == practiceID }
            .map { ($0.questionID, $0) })
    }

    static func answer(questionID: String, in context: ModelContext) throws -> ShenlunWorkspaceAnswer? {
        try value(ShenlunWorkspaceAnswer.self, id: questionID, collection: answerCollection, in: context)
    }

    static func drawing(id: String, in context: ModelContext) throws -> ShenlunWorkspaceDrawing? {
        try value(ShenlunWorkspaceDrawing.self, id: id, collection: drawingCollection, in: context)
    }

    static func drawings(
        practiceID: String,
        materialID: String,
        materialVersionID: String,
        pageID: String,
        in context: ModelContext
    ) throws -> [ShenlunWorkspaceDrawing] {
        let collectionKey = drawingCollection
        let prefix = drawingRecordPrefix(
            practiceID: practiceID,
            materialID: materialID,
            materialVersionID: materialVersionID,
            pageID: pageID
        )
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
            $0.collection == collectionKey && $0.recordID.hasPrefix(prefix)
        })
        return try context.fetch(descriptor).compactMap { try? decode(ShenlunWorkspaceDrawing.self, from: $0.payload) }
    }

    static func drawingRecordID(
        practiceID: String,
        materialID: String,
        materialVersionID: String,
        pageID: String,
        layerID: String
    ) -> String {
        drawingRecordPrefix(practiceID: practiceID, materialID: materialID, materialVersionID: materialVersionID, pageID: pageID) + layerID
    }

    private static func drawingRecordPrefix(
        practiceID: String,
        materialID: String,
        materialVersionID: String,
        pageID: String
    ) -> String {
        [practiceID, materialID, materialVersionID, pageID].joined(separator: "|") + "|"
    }

    static func deleteDrawing(id: String, in context: ModelContext) throws {
        let recordKey = id
        let collectionKey = drawingCollection
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
            $0.collection == collectionKey && $0.recordID == recordKey
        })
        guard let existing = try context.fetch(descriptor).first else { return }
        try context.transaction { context.delete(existing) }
        try context.save()
    }

    static func saveNewPractice(
        _ practice: ShenlunWorkspacePractice,
        firstQuestion: ShenlunWorkspaceQuestion,
        in context: ModelContext
    ) throws {
        try save([
            try payload(practice, id: practice.id, collection: practiceCollection, createdAt: practice.createdAt, updatedAt: practice.updatedAt),
            try payload(firstQuestion, id: firstQuestion.id, collection: questionCollection, createdAt: practice.createdAt, updatedAt: practice.updatedAt)
        ], in: context)
    }

    static func savePracticeAndQuestion(
        _ practice: ShenlunWorkspacePractice,
        _ question: ShenlunWorkspaceQuestion,
        createdAt: Date,
        materials: [ShenlunWorkspaceMaterial] = [],
        assets: [ShenlunWorkspaceAsset] = [],
        answerUpdate: ShenlunWorkspaceAnswer? = nil,
        deletingMaterialIDs: [String] = [],
        deletingAssetIDs: [String] = [],
        in context: ModelContext
    ) throws {
        var payloads = try [
            try payload(practice, id: practice.id, collection: practiceCollection, createdAt: createdAt, updatedAt: practice.updatedAt),
            try payload(question, id: question.id, collection: questionCollection, createdAt: createdAt, updatedAt: practice.updatedAt)
        ]
        payloads += try materials.map { try payload($0, id: $0.id, collection: materialCollection, createdAt: createdAt, updatedAt: practice.updatedAt) }
        payloads += try assets.map { try payload($0, id: $0.id, collection: assetCollection, createdAt: createdAt, updatedAt: practice.updatedAt) }
        if let answerUpdate {
            payloads.append(try payload(answerUpdate, id: answerUpdate.questionID, collection: answerCollection, createdAt: createdAt, updatedAt: practice.updatedAt))
        }
        let removedMaterials = try records(collection: materialCollection, in: context)
            .filter { deletingMaterialIDs.contains($0.recordID) }
        let removedAssets = try records(collection: assetCollection, in: context)
            .filter { deletingAssetIDs.contains($0.recordID) }
        let removedDrawings = try records(collection: drawingCollection, in: context).filter { record in
            guard let drawing = try? decode(ShenlunWorkspaceDrawing.self, from: record.payload) else { return false }
            return deletingMaterialIDs.contains(drawing.materialID)
        }
        try context.transaction {
            removedMaterials.forEach { context.delete($0) }
            removedAssets.forEach { context.delete($0) }
            removedDrawings.forEach { context.delete($0) }
            try upsert(payloads, in: context)
        }
        try context.save()
    }

    static func save(_ value: ShenlunWorkspacePractice, in context: ModelContext) throws {
        try write(value, id: value.id, collection: practiceCollection, createdAt: value.createdAt, updatedAt: value.updatedAt, in: context)
    }

    static func save(_ value: ShenlunWorkspaceQuestion, in context: ModelContext) throws {
        try write(value, id: value.id, collection: questionCollection, updatedAt: .now, in: context)
    }

    static func save(_ value: ShenlunWorkspaceMaterial, in context: ModelContext) throws {
        try write(value, id: value.id, collection: materialCollection, updatedAt: .now, in: context)
    }

    static func save(_ value: ShenlunWorkspaceAsset, in context: ModelContext) throws {
        try write(value, id: value.id, collection: assetCollection, updatedAt: .now, in: context)
    }

    static func save(_ value: ShenlunWorkspaceAnswer, in context: ModelContext) throws {
        try write(value, id: value.questionID, collection: answerCollection, updatedAt: .now, in: context)
    }

    static func save(_ value: ShenlunWorkspaceDrawing, in context: ModelContext) throws {
        try write(value, id: value.id, collection: drawingCollection, updatedAt: value.updatedAt, in: context)
    }

    static func deletePractice(_ practice: ShenlunWorkspacePractice, in context: ModelContext) throws {
        let questionIDs = practice.questionIDs
        let materialIDs = practice.materialIDs
        let all = try context.fetch(FetchDescriptor<StoredRecord>())
        let related = all.filter { record in
            if record.collection == practiceCollection && record.recordID == practice.id { return true }
            if record.collection == questionCollection && questionIDs.contains(record.recordID) { return true }
            if record.collection == materialCollection && materialIDs.contains(record.recordID) { return true }
            if record.collection == answerCollection {
                return (try? decode(ShenlunWorkspaceAnswer.self, from: record.payload).practiceID) == practice.id
            }
            if record.collection == assetCollection {
                return (try? decode(ShenlunWorkspaceAsset.self, from: record.payload).practiceID) == practice.id
            }
            if record.collection == drawingCollection {
                return (try? decode(ShenlunWorkspaceDrawing.self, from: record.payload).practiceID) == practice.id
            }
            return false
        }
        try context.transaction {
            related.forEach(context.delete)
        }
        try context.save()
    }

    private static func values<Value: Decodable>(
        _ type: Value.Type,
        collection: String,
        in context: ModelContext
    ) throws -> [Value] {
        let collectionKey = collection
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.collection == collectionKey })
        return try context.fetch(descriptor).compactMap { try? decode(type, from: $0.payload) }
    }

    private static func records(collection: String, in context: ModelContext) throws -> [StoredRecord] {
        let collectionKey = collection
        return try context.fetch(FetchDescriptor<StoredRecord>(predicate: #Predicate { $0.collection == collectionKey }))
    }

    private static func value<Value: Decodable>(
        _ type: Value.Type,
        id: String,
        collection: String,
        in context: ModelContext
    ) throws -> Value? {
        let collectionKey = collection
        let recordKey = id
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
            $0.collection == collectionKey && $0.recordID == recordKey
        })
        return try context.fetch(descriptor).first.flatMap { try? decode(type, from: $0.payload) }
    }

    private static func write<Value: Encodable>(
        _ value: Value,
        id: String,
        collection: String,
        createdAt: Date? = nil,
        updatedAt: Date,
        in context: ModelContext
    ) throws {
        try save([payload(value, id: id, collection: collection, createdAt: createdAt, updatedAt: updatedAt)], in: context)
    }

    private static func payload<Value: Encodable>(
        _ value: Value,
        id: String,
        collection: String,
        createdAt: Date? = nil,
        updatedAt: Date
    ) throws -> PendingPayload {
        PendingPayload(
            collection: collection,
            id: id,
            payload: try JSONEncoder().encode(value),
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    private static func save(_ payloads: [PendingPayload], in context: ModelContext) throws {
        let existingByID = Dictionary(uniqueKeysWithValues: try payloads.compactMap { payload -> (String, StoredRecord)? in
            let collectionKey = payload.collection
            let recordKey = payload.id
            let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                $0.collection == collectionKey && $0.recordID == recordKey
            })
            return try context.fetch(descriptor).first.map { ($0.compoundID, $0) }
        })
        try context.transaction { try upsert(payloads, existingByID: existingByID, in: context) }
        try context.save()
    }

    private static func upsert(_ payloads: [PendingPayload], in context: ModelContext) throws {
        let existingByID = Dictionary(uniqueKeysWithValues: try payloads.compactMap { payload -> (String, StoredRecord)? in
            let collectionKey = payload.collection
            let recordKey = payload.id
            let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                $0.collection == collectionKey && $0.recordID == recordKey
            })
            return try context.fetch(descriptor).first.map { ($0.compoundID, $0) }
        })
        try upsert(payloads, existingByID: existingByID, in: context)
    }

    private static func upsert(
        _ payloads: [PendingPayload],
        existingByID: [String: StoredRecord],
        in context: ModelContext
    ) throws {
        for payload in payloads {
            let compoundID = "\(payload.collection):\(payload.id)"
            if let existing = existingByID[compoundID] {
                existing.replacePayload(try merging(payload.payload, over: existing.payload))
                existing.updatedAt = payload.updatedAt
            } else {
                context.insert(StoredRecord(
                    collection: payload.collection,
                    recordID: payload.id,
                    payload: payload.payload,
                    subject: "申论",
                    createdAt: payload.createdAt ?? payload.updatedAt,
                    updatedAt: payload.updatedAt
                ))
            }
        }
    }

    private static func merging(_ encoded: Data, over existing: Data) throws -> Data {
        guard var stored = (try? JSONSerialization.jsonObject(with: existing)) as? [String: Any],
              let update = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return encoded }
        for (key, value) in update { stored[key] = value }
        return try JSONSerialization.data(withJSONObject: stored, options: [.sortedKeys, .withoutEscapingSlashes])
    }

    private static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try JSONDecoder().decode(type, from: data)
    }
}
