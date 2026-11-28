import Foundation
import SwiftData

enum LibraryErrorTypeSubject: String, CaseIterable, Hashable {
    case dataAnalysis = "资料分析"
    case verbalReasoning = "言语理解"
    case judgmentReasoning = "判断推理"
    case commonKnowledge = "常识判断"

    var recordID: String {
        switch self {
        case .dataAnalysis: "data_analysis_error_types"
        case .verbalReasoning: "verbal_reasoning_error_types"
        case .judgmentReasoning: "judgment_reasoning_question_types"
        case .commonKnowledge: "common_knowledge_question_types"
        }
    }

    var managementTitle: String { "\(rawValue)题型管理" }

    var modules: [String] {
        return SubjectDefinition.all.first { $0.name == rawValue }?.modules ?? []
    }

    func accepts(_ type: LibraryErrorType, in module: String) -> Bool {
        switch self {
        case .dataAnalysis: true
        case .verbalReasoning: type.module == module
        case .judgmentReasoning, .commonKnowledge: type.isAvailable(in: module)
        }
    }
}

struct LibraryErrorType: Identifiable, Equatable {
    let id: String
    var name: String
    var module: String? = nil

    func isAvailable(in module: String) -> Bool {
        self.module == nil || self.module == module
    }
}

enum LibraryErrorTypeFilter: Hashable {
    case all
    case unclassified
    case type(String)

    var selectedID: String? {
        if case let .type(id) = self { return id }
        return nil
    }

    func includes(_ recordTypeID: String?, validIDs: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .unclassified: recordTypeID.map { !validIDs.contains($0) } ?? true
        case let .type(id): recordTypeID == id && validIDs.contains(id)
        }
    }
}

enum LibraryErrorTypeRepository {
    static func types(for subject: LibraryErrorTypeSubject, records: [StoredRecord]) -> [LibraryErrorType] {
        guard let record = catalogRecord(for: subject, records: records),
              let values = record.jsonObject?["value"] as? [[String: String]] else { return [] }
        var ids = Set<String>()
        return values.compactMap { value in
            guard let id = value["id"], !id.isEmpty,
                  let name = value["name"], !name.isEmpty,
                  ids.insert(id).inserted else { return nil }
            return LibraryErrorType(id: id, name: name, module: value["module"])
        }
    }

    static func save(
        _ types: [LibraryErrorType],
        for subject: LibraryErrorTypeSubject,
        module: String?,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let otherModules = subject == .dataAnalysis
            ? [] : self.types(for: subject, records: records).filter { $0.module != module }
        let value = (otherModules + types).map { type in
            var entry = ["id": type.id, "name": type.name]
            entry["module"] = type.module
            return entry
        }
        let object: [String: Any] = ["key": subject.recordID, "value": value]
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let existing = catalogRecord(for: subject, records: records)
        try context.transaction {
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = .now
            } else {
                context.insert(StoredRecord(
                    collection: "keyvalue", recordID: subject.recordID, payload: payload, updatedAt: .now
                ))
            }
        }
    }

    private static func catalogRecord(for subject: LibraryErrorTypeSubject, records: [StoredRecord]) -> StoredRecord? {
        records.first { $0.collection == "keyvalue" && $0.recordID == subject.recordID }
    }
}
