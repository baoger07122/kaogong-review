import Foundation
import SwiftData

struct LogicComparisonDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var words = ""
    var relation = ""
}

struct ShenlunBiasDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var wrong = ""
    var right = ""
}

struct LibraryRecordDraft {
    var original: [String: Any] = [:]
    var id = ""
    var subject = "言语理解"
    var module = "逻辑填空"
    var title = ""
    var content = ""
    var type = ""
    var knowledgePoint = ""
    var errorCause = ""
    var status = "未掌握"
    var options = ["", "", "", ""]
    var correctOption = ""
    var userOption = ""
    var pitfall = ""
    var questionSource = ""
    var images: [String] = []
    var compareGroups: [LogicComparisonDraft] = []
    var score = ""
    var totalScore = ""
    var myFramework = ""
    var standardFramework = ""
    var paragraph = ""
    var bias: [ShenlunBiasDraft] = []
    var wrongList: [String] = []
    var missedList: [String] = []
    var graphRule = ""
    var recognition = ""
    var pencilKitData = ""
    var legacyDrawingPreview = ""
    var mindMapData = ""
    var sourceExamID = ""
    var linkedErrorIDs: [String] = []
    var linkedNoteIDs: [String] = []
    var linkedWordIDs: [String] = []
    var colorHex = "#FFFFFF"
    var pinned = false

    init(kind: LibraryContentKind, scope: LibraryScope, record: StoredRecord? = nil) {
        original = record?.jsonObject ?? [:]
        id = record?.recordID ?? ""
        subject = (original["subject"] as? String) ?? scope.subject ?? "言语理解"
        let defaultModules = SubjectDefinition.all.first { $0.name == subject }?.modules ?? []
        module = (original["module"] as? String) ?? scope.module ?? defaultModules.first ?? ""
        title = LibraryRecordDraft.text(original, keys: ["title", "question", "words", "text"])
        content = LibraryRecordDraft.text(original, keys: ["content", "note", "meaning", "myUnderstanding"])
        type = LibraryRecordDraft.text(original, keys: ["type", "tag", "category"])
        knowledgePoint = LibraryRecordDraft.text(original, keys: ["knowledgePoint"])
        if let values = original["knowledgePoints"] as? [String], !values.isEmpty {
            knowledgePoint = values.joined(separator: "、")
        }
        errorCause = LibraryRecordDraft.text(original, keys: ["errorCause"])
        status = LibraryRecordDraft.text(original, keys: ["status", "masteryStatus"]).isEmpty ? "未掌握" : LibraryRecordDraft.text(original, keys: ["status", "masteryStatus"])
        if let values = original["options"] as? [String], !values.isEmpty {
            options = values + Array(repeating: "", count: max(0, 4 - values.count))
        }
        correctOption = LibraryRecordDraft.text(original, keys: ["correctOption"])
        userOption = LibraryRecordDraft.text(original, keys: ["userOption"])
        pitfall = LibraryRecordDraft.text(original, keys: ["pitfall"])
        questionSource = LibraryRecordDraft.text(original, keys: ["questionSource", "source"])
        images = (original["images"] as? [String]) ?? (original["image"] as? String).map { [$0] } ?? []
        if let groups = original["compareGroups"] as? [[String: Any]] {
            compareGroups = groups.map { .init(words: $0["words"] as? String ?? "", relation: $0["relation"] as? String ?? "") }
        }
        score = LibraryRecordDraft.numberText(original["score"])
        totalScore = LibraryRecordDraft.numberText(original["totalScore"])
        myFramework = LibraryRecordDraft.text(original, keys: ["myFramework"])
        standardFramework = LibraryRecordDraft.text(original, keys: ["stdFramework"])
        paragraph = LibraryRecordDraft.text(original, keys: ["paragraph"])
        if let rows = original["bias"] as? [[String: Any]] {
            bias = rows.map { .init(wrong: $0["wrong"] as? String ?? "", right: $0["right"] as? String ?? "") }
        }
        wrongList = original["wrongList"] as? [String] ?? []
        missedList = original["missedList"] as? [String] ?? []
        graphRule = LibraryRecordDraft.text(original, keys: ["graphRule", "patternRule"])
        recognition = LibraryRecordDraft.text(original, keys: ["recognition", "recognitionPath"])
        pencilKitData = LibraryRecordDraft.text(original, keys: ["pencilKitData", "drawingData"])
        legacyDrawingPreview = LibraryRecordDraft.text(original, keys: ["legacyDrawingPreview", "drawingPreview", "handNote", "doodle"])
        mindMapData = LibraryRecordDraft.text(original, keys: ["mindMap", "mindMapData"])
        sourceExamID = LibraryRecordDraft.text(original, keys: ["sourceExamId"])
        linkedErrorIDs = original["linkedErrors"] as? [String] ?? []
        linkedNoteIDs = original["linkedNoteIds"] as? [String] ?? []
        linkedWordIDs = original["linkedWordIds"] as? [String] ?? []
        colorHex = LibraryRecordDraft.text(original, keys: ["color", "colorHex"]).isEmpty ? "#FFFFFF" : LibraryRecordDraft.text(original, keys: ["color", "colorHex"])
        pinned = (original["pinned"] as? Bool) ?? false

        if kind == .stickies {
            content = LibraryRecordDraft.text(original, keys: ["content", "text"])
        }
        if kind == .errors, subject == "申论" {
            status = LibraryRecordDraft.text(original, keys: ["status"]).isEmpty ? "待吸收" : LibraryRecordDraft.text(original, keys: ["status"])
        }
    }

    private static func text(_ object: [String: Any], keys: [String]) -> String {
        for key in keys where object[key] is String { return object[key] as? String ?? "" }
        return ""
    }

    private static func numberText(_ value: Any?) -> String {
        if let value = value as? NSNumber { return value.stringValue }
        return value as? String ?? ""
    }
}

enum LibraryRecordRepository {
    static func save(
        kind: LibraryContentKind,
        draft: LibraryRecordDraft,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let now = Date()
        let id = draft.id.isEmpty ? makeID(kind: kind) : draft.id
        let existing = records.first { $0.collection == kind.collection && $0.recordID == id }
        var object = draft.original
        let previousSourceExamID = object["sourceExamId"] as? String ?? ""
        let previousLinkedErrors = object["linkedErrors"] as? [String] ?? []
        let previousLinkedNotes = object["linkedNoteIds"] as? [String] ?? []
        let previousLinkedWords = object["linkedWordIds"] as? [String] ?? []
        object["id"] = id
        object["subject"] = draft.subject
        object["module"] = draft.module
        object["updatedAt"] = iso(now)
        object["createdAt"] = object["createdAt"] ?? iso(existing?.createdAt ?? now)

        switch kind {
        case .errors:
            let knowledgePoints = draft.knowledgePoint
                .split(whereSeparator: { "、,，".contains($0) })
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            object["question"] = draft.title
            object["note"] = draft.content
            object["knowledgePoints"] = knowledgePoints
            object["knowledgePoint"] = knowledgePoints.first ?? ""
            object["errorCause"] = draft.errorCause
            object["status"] = draft.status
            object["options"] = draft.options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            object["correctOption"] = draft.correctOption
            object["userOption"] = draft.userOption
            object["pitfall"] = draft.pitfall
            object["questionSource"] = draft.questionSource
            object["images"] = draft.images
            object["compareGroups"] = draft.compareGroups
                .filter { !$0.words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !$0.relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .map { ["words": $0.words, "relation": $0.relation] }
            object["graphRule"] = draft.graphRule
            object["recognition"] = draft.recognition
            object["sourceExamId"] = draft.sourceExamID.isEmpty ? NSNull() : draft.sourceExamID
            object["linkedNoteIds"] = draft.linkedNoteIDs
            object["linkedWordIds"] = draft.linkedWordIDs
            object["pencilKitData"] = draft.pencilKitData
            let generatedDrawingPreview = PencilDrawingCompatibility.previewDataURL(encodedData: draft.pencilKitData)
            if draft.legacyDrawingPreview.isEmpty {
                object["drawingPreview"] = generatedDrawingPreview
                object["handNote"] = generatedDrawingPreview
            } else {
                object["legacyDrawingPreview"] = draft.legacyDrawingPreview
                object["drawingPreview"] = draft.legacyDrawingPreview
            }
            object["reviewCount"] = object["reviewCount"] ?? 0
            object["lastReviewDate"] = object["lastReviewDate"] ?? iso(now)
            if draft.subject == "申论" {
                object["isShenlun"] = true
                object["score"] = Int(draft.score) ?? 0
                object["totalScore"] = Int(draft.totalScore) ?? 0
                object["source"] = draft.questionSource
                object["myFramework"] = draft.myFramework
                object["stdFramework"] = draft.standardFramework
                object["paragraph"] = draft.paragraph
                object["bias"] = draft.bias.filter { !$0.wrong.isEmpty || !$0.right.isEmpty }.map { ["wrong": $0.wrong, "right": $0.right] }
                object["wrongList"] = draft.wrongList.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                object["missedList"] = draft.missedList.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                object["knowledgePoints"] = []
                object["options"] = []
                object["errorCause"] = ""
            }
        case .notes:
            object["title"] = draft.title
            object["content"] = draft.content
            object["type"] = draft.type
            object["knowledgePoint"] = draft.knowledgePoint
            object["linkedErrors"] = draft.linkedErrorIDs
            object["linkedReviews"] = object["linkedReviews"] ?? []
            object["mindMap"] = draft.mindMapData
            object["pencilKitData"] = draft.pencilKitData
            let generatedDrawingPreview = PencilDrawingCompatibility.previewDataURL(encodedData: draft.pencilKitData)
            if draft.legacyDrawingPreview.isEmpty {
                object["drawingPreview"] = generatedDrawingPreview
                object["doodle"] = generatedDrawingPreview
            } else {
                object["legacyDrawingPreview"] = draft.legacyDrawingPreview
                object["drawingPreview"] = draft.legacyDrawingPreview
            }
        case .stickies:
            object["content"] = draft.content
            object["tag"] = draft.type.trimmingCharacters(in: .whitespacesAndNewlines)
            object["color"] = draft.colorHex
            object["pinned"] = draft.pinned
        case .words:
            object["words"] = draft.title
            object["meaning"] = draft.content
            object["type"] = draft.type
            object["linkedErrors"] = draft.linkedErrorIDs
        }

        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        if let existing {
            existing.payload = payload
            existing.subject = draft.subject
            existing.module = draft.module
            existing.updatedAt = now
        } else {
            context.insert(StoredRecord(
                collection: kind.collection,
                recordID: id,
                payload: payload,
                subject: draft.subject,
                module: draft.module,
                createdAt: now,
                updatedAt: now
            ))
        }
        switch kind {
        case .errors:
            try syncSingleRelation(collection: "exams", arrayKey: "linkedErrorIds", oldID: previousSourceExamID, newID: draft.sourceExamID, linkedID: id, records: records)
            try syncArrayRelations(collection: "notes", arrayKey: "linkedErrors", oldIDs: previousLinkedNotes, newIDs: draft.linkedNoteIDs, linkedID: id, records: records)
            try syncArrayRelations(collection: "words", arrayKey: "linkedErrors", oldIDs: previousLinkedWords, newIDs: draft.linkedWordIDs, linkedID: id, records: records)
        case .notes:
            try syncArrayRelations(collection: "errors", arrayKey: "linkedNoteIds", oldIDs: previousLinkedErrors, newIDs: draft.linkedErrorIDs, linkedID: id, records: records)
        case .words:
            try syncArrayRelations(collection: "errors", arrayKey: "linkedWordIds", oldIDs: previousLinkedErrors, newIDs: draft.linkedErrorIDs, linkedID: id, records: records)
        case .stickies:
            break
        }
        try context.save()
    }

    static func remove(kind: LibraryContentKind, id: String, records: [StoredRecord], context: ModelContext) throws {
        guard let record = records.first(where: { $0.collection == kind.collection && $0.recordID == id }) else { return }
        let object = record.jsonObject ?? [:]
        switch kind {
        case .errors:
            try syncSingleRelation(
                collection: "exams", arrayKey: "linkedErrorIds",
                oldID: object["sourceExamId"] as? String ?? "", newID: "", linkedID: id, records: records
            )
            try syncArrayRelations(
                collection: "notes", arrayKey: "linkedErrors",
                oldIDs: object["linkedNoteIds"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
            )
            try syncArrayRelations(
                collection: "words", arrayKey: "linkedErrors",
                oldIDs: object["linkedWordIds"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
            )
        case .notes:
            try syncArrayRelations(
                collection: "errors", arrayKey: "linkedNoteIds",
                oldIDs: object["linkedErrors"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
            )
        case .words:
            try syncArrayRelations(
                collection: "errors", arrayKey: "linkedWordIds",
                oldIDs: object["linkedErrors"] as? [String] ?? [], newIDs: [], linkedID: id, records: records
            )
        case .stickies:
            break
        }
        context.delete(record)
        try context.save()
    }

    private static func makeID(kind: LibraryContentKind) -> String {
        let prefix: String
        switch kind {
        case .errors: prefix = "err"
        case .notes: prefix = "note"
        case .stickies: prefix = "sticky"
        case .words: prefix = "word"
        }
        return "\(prefix)_\(Int(Date().timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))"
    }

    private static func syncSingleRelation(
        collection: String, arrayKey: String, oldID: String, newID: String,
        linkedID: String, records: [StoredRecord]
    ) throws {
        if !oldID.isEmpty, oldID != newID,
           let record = records.first(where: { $0.collection == collection && $0.recordID == oldID }) {
            try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: false)
        }
        if !newID.isEmpty,
           let record = records.first(where: { $0.collection == collection && $0.recordID == newID }) {
            try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: true)
        }
    }

    private static func syncArrayRelations(
        collection: String, arrayKey: String, oldIDs: [String], newIDs: [String],
        linkedID: String, records: [StoredRecord]
    ) throws {
        let oldSet = Set(oldIDs)
        let newSet = Set(newIDs)
        for relationID in oldSet.subtracting(newSet) {
            if let record = records.first(where: { $0.collection == collection && $0.recordID == relationID }) {
                try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: false)
            }
        }
        for relationID in newSet {
            if let record = records.first(where: { $0.collection == collection && $0.recordID == relationID }) {
                try updateRelation(record: record, key: arrayKey, linkedID: linkedID, include: true)
            }
        }
    }

    private static func updateRelation(record: StoredRecord, key: String, linkedID: String, include: Bool) throws {
        var object = record.jsonObject ?? [:]
        var values = Set(object[key] as? [String] ?? [])
        if include { values.insert(linkedID) } else { values.remove(linkedID) }
        object[key] = Array(values).sorted()
        object["updatedAt"] = iso(.now)
        record.payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        record.updatedAt = .now
    }

    private static func iso(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}
