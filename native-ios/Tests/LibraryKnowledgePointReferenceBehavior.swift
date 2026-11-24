import Foundation

@main
enum LibraryKnowledgePointReferenceBehavior {
    static func main() throws {
        let legacyObject: [String: Any] = [
            "knowledgePointRefs": [["module": "逻辑填空", "name": "语境分析"]],
            "knowledgePoints": ["语境分析"]
        ]
        let legacy = LibraryKnowledgePointReferencePolicy.references(from: legacyObject)
        precondition(legacy.count == 1)
        precondition(legacy[0].module == "逻辑填空")
        precondition(legacy[0].typeID == nil, "a legacy module reference must not be assigned to a guessed type")

        let typeA = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-a", name: "语境分析")
        let typeB = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-b", name: "语境分析")
        precondition(typeA.id != typeB.id)
        precondition(Set([typeA, typeB, typeA]).count == 2, "same-named points under different type IDs must remain distinct")

        let typedObject: [String: Any] = [
            "knowledgePointRefs": [typeA.jsonValue, typeB.jsonValue],
            "knowledgePoints": ["语境分析"]
        ]
        let decoded = LibraryKnowledgePointReferencePolicy.references(from: typedObject)
        precondition(decoded.count == 2)
        precondition(decoded.allSatisfy { $0.typeID != nil })
        precondition(Set(decoded.compactMap(\.typeID)) == Set<String>(["type-a", "type-b"]))

        let mixedLegacyObject: [String: Any] = [
            "knowledgePointRefs": [typeA.jsonValue],
            "knowledgePoints": ["语境分析", "旧版未迁移考点"]
        ]
        let mixed = LibraryKnowledgePointReferencePolicy.references(from: mixedLegacyObject)
        precondition(mixed.count == 2, "a mixed record must keep legacy names absent from its structured references")
        precondition(mixed.contains(typeA))
        precondition(mixed.contains(LibraryKnowledgePointReference(module: nil, name: "旧版未迁移考点")))

        let authoritativeEmpty = LibraryKnowledgePointReferencePolicy.references(from: [
            "knowledgePointRefs": [],
            "knowledgePoints": ["stale legacy value"],
            "knowledgePoint": "stale legacy value"
        ])
        precondition(authoritativeEmpty.isEmpty, "an explicit empty reference list must remain an intentional clear")

        let knownCommaName = LibraryKnowledgePointReferencePolicy.references(
            from: ["knowledgePoint": "综合,分析"], knownNames: ["综合,分析", "综合", "分析"]
        )
        precondition(knownCommaName.map(\.name) == ["综合,分析"], "an exact catalog name containing a comma must win over token splitting")

        let unambiguousLegacyList = LibraryKnowledgePointReferencePolicy.references(
            from: ["knowledgePoint": "综合、分析"], knownNames: ["综合", "分析"]
        )
        precondition(unambiguousLegacyList.map(\.name) == ["综合", "分析"])

        let ambiguousLegacyText = LibraryKnowledgePointReferencePolicy.references(
            from: ["knowledgePoint": "综合,陌生"], knownNames: ["综合"]
        )
        precondition(ambiguousLegacyText.map(\.name) == ["综合,陌生"], "unmatched legacy text must be preserved for review")

        let resolved = LibraryKnowledgePointReferencePolicy.resolvingLocalReferences(
            [LibraryKnowledgePointReference(module: nil, typeID: "type-a", name: "语境分析"),
             LibraryKnowledgePointReference(module: nil, name: "旧条目")],
            currentModule: "逻辑填空",
            availableNames: ["语境分析", "旧条目"]
        )
        precondition(resolved.first?.module == nil)
        precondition(resolved.first?.typeID == "type-a", "legacy reference handling must preserve an explicit type ID")
        precondition(resolved.last?.module == nil && resolved.last?.typeID == nil,
                     "a same-named library entry must not be used to infer a legacy reference's module or type")

        verifyCategoryMigration(typeA: typeA, typeB: typeB)

        var library: [String: Any] = [:]
        library = VerbalReasoningKnowledgePointLibraryPolicy.replacingTags(
            ["语境分析"], in: library, module: "逻辑填空", typeID: "type-a"
        )
        library = VerbalReasoningKnowledgePointLibraryPolicy.replacingTags(
            ["语境分析", "程度副词"], in: library, module: "逻辑填空", typeID: "type-b"
        )
        precondition(
            VerbalReasoningKnowledgePointLibraryPolicy.tags(from: library, module: "逻辑填空", typeID: "type-a") == ["语境分析"],
            "editing one type's list must not overwrite another type's list"
        )
        precondition(
            VerbalReasoningKnowledgePointLibraryPolicy.tags(from: library, module: "中心理解", typeID: "type-a").isEmpty,
            "same type IDs in a different module must remain isolated"
        )
    }

    private static func verifyCategoryMigration(
        typeA: LibraryKnowledgePointReference, typeB: LibraryKnowledgePointReference
    ) {
        let bare = LibraryKnowledgePointReference(module: nil, name: typeA.name)
        let typeOnly = LibraryKnowledgePointReference(module: nil, typeID: typeA.typeID, name: typeA.name)

        let forward = LibraryTagCategoryReferencePolicy.plan(
            knowledge: [typeA, typeB], mistakes: [typeA], tag: typeA, toMistakeTag: true,
            isLocalModule: false, localKnowledgeCandidates: [typeA, typeB], destinationExists: true
        )
        precondition(forward == .moved(knowledge: [typeB], mistakes: [typeA]),
                     "a qualified cross-module reference migrates without altering a same-named reference")

        let uniqueLegacy = LibraryTagCategoryReferencePolicy.plan(
            knowledge: [bare, typeOnly], mistakes: [], tag: typeA, toMistakeTag: true,
            isLocalModule: true, localKnowledgeCandidates: [typeA], destinationExists: false
        )
        precondition(uniqueLegacy == .moved(knowledge: [], mistakes: [typeA]))

        let ambiguousLegacy = LibraryTagCategoryReferencePolicy.plan(
            knowledge: [bare], mistakes: [], tag: typeA, toMistakeTag: true,
            isLocalModule: true, localKnowledgeCandidates: [typeA, typeB], destinationExists: false
        )
        precondition(ambiguousLegacy == .ambiguous)

        let reverse = LibraryTagCategoryReferencePolicy.plan(
            knowledge: [bare], mistakes: [typeA, typeB], tag: typeA, toMistakeTag: false,
            isLocalModule: true, localKnowledgeCandidates: [typeA, typeB], destinationExists: false
        )
        precondition(reverse == .moved(knowledge: [typeB, typeA], mistakes: [typeB]),
                     "an existing legacy association to the only prior label stays separate from the new reference")
    }
}
