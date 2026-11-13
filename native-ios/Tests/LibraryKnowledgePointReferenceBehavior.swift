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
}
