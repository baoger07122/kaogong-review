import Foundation

struct LibraryKnowledgePointReference: Codable, Equatable, Hashable, Identifiable, Sendable {
    var module: String?
    var typeID: String? = nil
    var name: String

    var id: String { "\(module ?? "")\u{1f}\(typeID ?? "")\u{1f}\(name)" }

    var jsonValue: [String: String] {
        var value = ["module": module ?? "", "name": name]
        value["typeID"] = typeID
        return value
    }
}

enum LibraryKnowledgePointReferencePolicy {
    static func references(from object: [String: Any], fallbackValue: String = "") -> [LibraryKnowledgePointReference] {
        if let values = object["knowledgePointRefs"] as? [[String: Any]] {
            let decoded = values.compactMap { value -> LibraryKnowledgePointReference? in
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
            let knownNames = Set(decoded.map(\.name))
            let legacyValues = object["knowledgePoints"] as? [String]
                ?? splitNames((object["knowledgePoint"] as? String) ?? fallbackValue)
            let preservedLegacy = legacyValues.compactMap { name -> LibraryKnowledgePointReference? in
                let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !knownNames.contains(value) else { return nil }
                return LibraryKnowledgePointReference(module: nil, name: value)
            }
            return uniqueReferences(decoded + preservedLegacy)
        }

        let values = object["knowledgePoints"] as? [String]
        let names = values?.isEmpty == false
            ? values ?? []
            : splitNames((object["knowledgePoint"] as? String) ?? fallbackValue)
        return uniqueReferences(names.compactMap { name -> LibraryKnowledgePointReference? in
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : LibraryKnowledgePointReference(module: nil, name: value)
        })
    }

    static func resolvingLocalReferences(
        _ references: [LibraryKnowledgePointReference],
        currentModule _: String,
        availableNames _: Set<String>
    ) -> [LibraryKnowledgePointReference] {
        uniqueReferences(references)
    }

    static func displayNames(from references: [LibraryKnowledgePointReference]) -> [String] {
        var seen = Set<String>()
        return references.map(\.name).filter { seen.insert($0).inserted }
    }

    static func uniqueReferences(_ references: [LibraryKnowledgePointReference]) -> [LibraryKnowledgePointReference] {
        var seen = Set<LibraryKnowledgePointReference>()
        return references.filter { seen.insert($0).inserted }
    }

    private static func splitNames(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
    }
}
