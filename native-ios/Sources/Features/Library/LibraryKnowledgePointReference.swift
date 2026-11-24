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
    static func references(
        from object: [String: Any],
        fallbackValue: String = "",
        knownNames: Set<String> = []
    ) -> [LibraryKnowledgePointReference] {
        if object.keys.contains("knowledgePointRefs"),
           let values = object["knowledgePointRefs"] as? [[String: Any]] {
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
            guard !decoded.isEmpty else { return [] }
            let decodedNames = Set(decoded.map(\.name))
            let legacyNames: [String]
            if let values = object["knowledgePoints"] as? [String] {
                legacyNames = values
            } else {
                let legacyValue = (object["knowledgePoint"] as? String) ?? fallbackValue
                let trimmed = legacyValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty || decodedNames.contains(trimmed) {
                    legacyNames = []
                } else {
                    let known = knownNames.union(decodedNames)
                    let pieces = splitNames(trimmed).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    legacyNames = pieces.count > 1
                        && pieces.allSatisfy({ !$0.isEmpty && known.contains($0) })
                        && Set(pieces).count == pieces.count
                        ? pieces
                        : [trimmed]
                }
            }
            let preservedLegacy = legacyNames.compactMap { name -> LibraryKnowledgePointReference? in
                let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !value.isEmpty, !decodedNames.contains(value) else { return nil }
                return LibraryKnowledgePointReference(module: nil, name: value)
            }
            return uniqueReferences(decoded + preservedLegacy)
        }

        if let values = object["knowledgePoints"] as? [String], !values.isEmpty {
            return uniqueReferences(values.compactMap(referenceIfNonempty))
        }
        let raw = (object["knowledgePoint"] as? String) ?? fallbackValue
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if knownNames.contains(trimmed) {
            return [LibraryKnowledgePointReference(module: nil, name: trimmed)]
        }
        let pieces = splitNames(trimmed).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let names: [String]
        if pieces.count > 1,
           pieces.allSatisfy({ !$0.isEmpty && knownNames.contains($0) }),
           Set(pieces).count == pieces.count {
            names = pieces
        } else {
            names = [trimmed]
        }
        return uniqueReferences(names.compactMap { name -> LibraryKnowledgePointReference? in
            referenceIfNonempty(name)
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

    private static func referenceIfNonempty(_ name: String) -> LibraryKnowledgePointReference? {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : LibraryKnowledgePointReference(module: nil, name: value)
    }
}

enum LibraryTagCategoryReferencePolicy {
    enum Plan: Equatable {
        case unchanged
        case ambiguous
        case moved(knowledge: [LibraryKnowledgePointReference], mistakes: [LibraryKnowledgePointReference])
    }

    static func plan(
        knowledge: [LibraryKnowledgePointReference],
        mistakes: [LibraryKnowledgePointReference],
        tag: LibraryKnowledgePointReference,
        toMistakeTag: Bool,
        isLocalModule: Bool,
        localKnowledgeCandidates: [LibraryKnowledgePointReference],
        destinationExists: Bool
    ) -> Plan {
        func isBareName(_ value: LibraryKnowledgePointReference) -> Bool {
            isLocalModule && value.name == tag.name && value.module == nil && value.typeID == nil
        }
        func matchesSource(_ value: LibraryKnowledgePointReference) -> Bool {
            value == tag || (isLocalModule && value.name == tag.name && value.module == nil
                && value.typeID != nil && value.typeID == tag.typeID)
        }
        var updatedKnowledge = knowledge
        var updatedMistakes = mistakes
        let hasBareName = knowledge.contains(where: isBareName)
        if toMistakeTag {
            if hasBareName, localKnowledgeCandidates != [tag] { return .ambiguous }
            updatedKnowledge.removeAll { matchesSource($0) || isBareName($0) }
            guard updatedKnowledge != knowledge else { return .unchanged }
            updatedMistakes.append(tag)
        } else {
            guard mistakes.contains(where: matchesSource) else { return .unchanged }
            if hasBareName {
                let previousCandidates = localKnowledgeCandidates.filter { $0 != tag }
                if previousCandidates.count > 1 || (destinationExists && !previousCandidates.isEmpty) {
                    return .ambiguous
                }
                updatedKnowledge = knowledge.compactMap { isBareName($0) ? previousCandidates.first : $0 }
            }
            updatedMistakes.removeAll(where: matchesSource)
            updatedKnowledge.append(tag)
        }
        return .moved(
            knowledge: LibraryKnowledgePointReferencePolicy.uniqueReferences(updatedKnowledge),
            mistakes: LibraryKnowledgePointReferencePolicy.uniqueReferences(updatedMistakes)
        )
    }
}
