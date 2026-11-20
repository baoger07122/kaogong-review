import Foundation

enum LibraryMistakeTagPolicy {
    static func scopeKey(subject: String, module: String, typeID: String?) -> String {
        "\(subject)\u{1f}\(module)\u{1f}\(typeID ?? "")"
    }

    static func references(from object: [String: Any]) -> [LibraryKnowledgePointReference] {
        guard let values = object["mistakeTagRefs"] as? [[String: Any]] else { return [] }
        let references = values.compactMap { value -> LibraryKnowledgePointReference? in
            guard let name = (value["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty else { return nil }
            let module = (value["module"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let typeID = (value["typeID"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return LibraryKnowledgePointReference(
                module: module?.isEmpty == false ? module : nil,
                typeID: typeID?.isEmpty == false ? typeID : nil,
                name: name
            )
        }
        return LibraryKnowledgePointReferencePolicy.uniqueReferences(references)
    }

    static func replacing(
        _ references: [LibraryKnowledgePointReference],
        from source: LibraryKnowledgePointReference,
        to destination: LibraryKnowledgePointReference?
    ) -> [LibraryKnowledgePointReference] {
        let updated = references.compactMap { reference -> LibraryKnowledgePointReference? in
            guard reference == source else { return reference }
            return destination
        }
        return LibraryKnowledgePointReferencePolicy.uniqueReferences(updated)
    }
}
