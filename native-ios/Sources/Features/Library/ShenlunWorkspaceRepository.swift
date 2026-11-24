import Foundation
import SwiftData

enum ShenlunWorkspaceRepository {
    static let practiceCollection = "shenlun_workspace_practices"
    static let questionCollection = "shenlun_workspace_questions"
    static let materialCollection = "shenlun_workspace_materials"
    static let assetCollection = "shenlun_workspace_assets"
    static let answerCollection = "shenlun_workspace_answers"
    static let attemptCollection = "shenlun_workspace_attempt_history"
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

    static func attemptHistories(practiceID: String? = nil, in context: ModelContext) throws -> [String: ShenlunWorkspaceAttemptHistory] {
        let readContext = ModelContext(context.container)
        let histories = try values(ShenlunWorkspaceAttemptHistory.self, collection: attemptCollection, in: readContext)
        var result: [String: ShenlunWorkspaceAttemptHistory] = [:]
        for history in histories where practiceID == nil || history.practiceID == practiceID {
            result[history.questionID] = history
        }
        for answer in try values(ShenlunWorkspaceAnswer.self, collection: answerCollection, in: readContext)
            where (practiceID == nil || answer.practiceID == practiceID) && result[answer.questionID] == nil {
            result[answer.questionID] = .init(practiceID: answer.practiceID, questionID: answer.questionID, legacy: answer)
        }
        return result
    }

    private static func attemptHistory(practiceID: String, questionID: String, in context: ModelContext) throws -> ShenlunWorkspaceAttemptHistory {
        let collection = attemptCollection
        let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
            $0.collection == collection && $0.recordID == questionID
        })
        if let record = try context.fetch(descriptor).first {
            return try decode(ShenlunWorkspaceAttemptHistory.self, from: record.payload)
        }
        let legacy = try value(ShenlunWorkspaceAnswer.self, id: questionID, collection: answerCollection, in: context)
        return .init(practiceID: practiceID, questionID: questionID, legacy: legacy)
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
            $0.collection == collectionKey && $0.recordID.starts(with: prefix)
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
        questions: [ShenlunWorkspaceQuestion],
        materials: [ShenlunWorkspaceMaterial],
        assets: [ShenlunWorkspaceAsset],
        in context: ModelContext
    ) throws {
        let payloads = try practicePayloads(
            practice, questions: questions, materials: materials, assets: assets, createdAt: practice.createdAt
        )
        let writeContext = ModelContext(context.container)
        writeContext.autosaveEnabled = false
        try writeContext.transaction { try upsert(payloads, in: writeContext) }
    }

    static func savePracticeAndQuestion(
        _ practice: ShenlunWorkspacePractice,
        _ question: ShenlunWorkspaceQuestion,
        createdAt: Date,
        materials: [ShenlunWorkspaceMaterial] = [],
        assets: [ShenlunWorkspaceAsset] = [],
        markScoresForReview: Bool = false,
        deletingMaterialIDs: [String] = [],
        deletingAssetIDs: [String] = [],
        in context: ModelContext
    ) throws {
        var payloads = try practicePayloads(
            practice, questions: [question], materials: materials, assets: assets, createdAt: createdAt
        )
        if markScoresForReview {
            let readContext = ModelContext(context.container)
            var history = try attemptHistory(practiceID: practice.id, questionID: question.id, in: readContext)
            let scored = history.attempts.indices.filter { history.attempts[$0].confirmedScore != nil }
            if !scored.isEmpty {
                for index in scored {
                    history.attempts[index].reviewState = .needsReview
                    history.attempts[index].revision += 1
                }
                payloads.append(try payload(history, id: question.id, collection: attemptCollection, updatedAt: practice.updatedAt))
            }
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

    private static func practicePayloads(
        _ practice: ShenlunWorkspacePractice,
        questions: [ShenlunWorkspaceQuestion],
        materials: [ShenlunWorkspaceMaterial],
        assets: [ShenlunWorkspaceAsset],
        createdAt: Date
    ) throws -> [PendingPayload] {
        func entry<Value: Encodable>(_ value: Value, id: String, collection: String) throws -> PendingPayload {
            try payload(value, id: id, collection: collection, createdAt: createdAt, updatedAt: practice.updatedAt)
        }
        var payloads = [try entry(practice, id: practice.id, collection: practiceCollection)]
        payloads += try questions.map { try entry($0, id: $0.id, collection: questionCollection) }
        payloads += try materials.map { try entry($0, id: $0.id, collection: materialCollection) }
        payloads += try assets.map { try entry($0, id: $0.id, collection: assetCollection) }
        return payloads
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

    static func saveAttempt(
        _ value: ShenlunWorkspaceAnswer,
        replacingRevision: Int?,
        in context: ModelContext
    ) throws -> ShenlunWorkspaceAttemptHistory {
        let writeContext = ModelContext(context.container)
        writeContext.autosaveEnabled = false
        var history = try attemptHistory(practiceID: value.practiceID, questionID: value.questionID, in: writeContext)
        let index = history.attempts.firstIndex { $0.id == value.id }
        guard index.map({ history.attempts[$0].revision }) == replacingRevision,
              value.isCompleted || history.draft == nil || history.draft?.id == value.id else {
            throw AttemptWriteError.changed
        }
        var updated = value
        updated.revision = (replacingRevision ?? 0) + 1
        if let index {
            guard !history.attempts[index].isCompleted || updated.isCompleted else { throw AttemptWriteError.changed }
            if updated.isCompleted && !history.attempts[index].isCompleted {
                updated.attemptNumber = history.nextNumber
            }
            history.attempts[index] = updated
        } else {
            if updated.isCompleted { updated.attemptNumber = history.nextNumber }
            history.attempts.append(updated)
        }
        let entry = try payload(history, id: value.questionID, collection: attemptCollection, updatedAt: .now)
        try writeContext.transaction { try upsert([entry], in: writeContext) }
        return history
    }

    private enum AttemptWriteError: LocalizedError {
        case changed

        var errorDescription: String? { "这次作答已在其他窗口更新。请重新打开题目后再保存。" }
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
            if record.collection == answerCollection || record.collection == attemptCollection {
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
                let data: Data
                if payload.collection == attemptCollection {
                    data = payload.payload
                } else {
                    data = try merging(payload.payload, over: existing.payload)
                }
                existing.replacePayload(data)
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
