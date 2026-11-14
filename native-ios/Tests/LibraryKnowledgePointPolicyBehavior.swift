import Foundation

@main
enum LibraryKnowledgePointPolicyBehavior {
    static func main() {
        let groupA = LibraryKnowledgePointGroup(id: "a", name: "排列", memberNames: ["相邻捆绑", "环形排列"])
        let groupB = LibraryKnowledgePointGroup(id: "b", name: "组合", memberNames: ["隔板法"])
        let groups = [groupA, groupB]
        precondition(LibraryKnowledgePointGroupPolicy.canUseGroupName(" 概率 ", groups: groups))
        precondition(!LibraryKnowledgePointGroupPolicy.canUseGroupName("排列", groups: groups))
        precondition(LibraryKnowledgePointGroupPolicy.canUseGroupName("排列", groups: groups, excluding: "a"))
        precondition(
            LibraryKnowledgePointGroupPolicy.scopeKey(subject: "数量关系", module: "排列组合", typeID: nil)
                != LibraryKnowledgePointGroupPolicy.scopeKey(subject: "资料分析", module: "排列组合", typeID: nil),
            "groups must remain scoped to their subject"
        )
        precondition(
            LibraryKnowledgePointGroupPolicy.scopeKey(subject: "言语理解", module: "逻辑填空", typeID: "type-a")
                != LibraryKnowledgePointGroupPolicy.scopeKey(subject: "言语理解", module: "逻辑填空", typeID: "type-b"),
            "groups must remain scoped to their error type"
        )

        let moved = LibraryKnowledgePointGroupPolicy.assign("隔板法", to: "a", in: groups)
        precondition(moved[0].memberNames.contains("隔板法"))
        precondition(!moved[1].memberNames.contains("隔板法"))
        let deleted = LibraryKnowledgePointGroupPolicy.deleteGroup("b", from: groups)
        precondition(!deleted.contains(where: { $0.id == "b" }))
        precondition(groups[1].memberNames == ["隔板法"], "deleting a group must not mutate the tag library")

        let fullOrder = ["相邻捆绑", "隔板法", "环形排列", "概率"]
        let reordered = LibraryKnowledgePointGroupPolicy.mergedOrder(
            fullOrder: fullOrder,
            groups: groups,
            groupID: groupA.id,
            displayedOrder: ["环形排列", "相邻捆绑"]
        )
        precondition(reordered == .some(["环形排列", "隔板法", "相邻捆绑", "概率"]))
        let ungroupedOrder = LibraryKnowledgePointGroupPolicy.mergedOrder(
            fullOrder: ["排列A", "未分组A", "排列B", "未分组B"],
            groups: [LibraryKnowledgePointGroup(id: "arrangement", name: "排列", memberNames: ["排列A", "排列B"])],
            groupID: nil,
            displayedOrder: ["未分组B", "未分组A"]
        )
        precondition(ungroupedOrder == .some(["排列A", "未分组B", "排列B", "未分组A"]))

        let typeA = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "a", name: "语境分析")
        let typeB = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "b", name: "语境分析")
        precondition(!LibraryKnowledgePointFilterPolicy.matches(
            recordReferences: [typeB], selectedReferences: [typeA]
        ), "same-named knowledge points in different types must not match")
        precondition(LibraryKnowledgePointFilterPolicy.matches(
            recordReferences: [typeA, typeB], selectedReferences: [typeA]
        ), "filter selection must use OR within its selected identities")
        precondition(LibraryKnowledgePointFilterPolicy.matches(
            recordReferences: [typeA, typeB], selectedReferences: [typeA, typeB]
        ), "multiple filters match any selected exact identity")
        precondition(!LibraryKnowledgePointFilterPolicy.matches(
            recordReferences: [LibraryKnowledgePointReference(module: "资料分析", name: "语境分析")],
            selectedReferences: [typeA]
        ), "same-named knowledge points in different modules must not match")

        let legacySource = LibraryKnowledgePointReference(module: "逻辑填空", name: "语境分析")
        let typedSource = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-a", name: "语境分析")
        let target = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-b", name: "语境分析")
        let otherSameName = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-c", name: "语境分析")
        let otherModule = LibraryKnowledgePointReference(module: "中心理解", typeID: "type-d", name: "语境分析")
        let legacyTarget = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [legacySource, target, otherModule], source: legacySource, destination: target,
            nameOnlyCandidates: [legacySource]
        )
        precondition(legacyTarget.didChange)
        precondition(legacyTarget.references == [target, otherModule])

        let typedTarget = LibraryKnowledgePointReference(module: "逻辑填空", typeID: "type-c", name: "语境分析")
        let exactTypedMove = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [typedSource, target], source: typedSource, destination: typedTarget,
            nameOnlyCandidates: [typedSource, target]
        )
        precondition(exactTypedMove.didChange)
        precondition(exactTypedMove.references == [typedTarget, target])

        let nameOnly = LibraryKnowledgePointReference(module: nil, name: "语境分析")
        let uniqueNameOnly = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [nameOnly], source: legacySource, destination: target,
            nameOnlyCandidates: [legacySource]
        )
        precondition(uniqueNameOnly.didChange && uniqueNameOnly.references == [target])

        let ambiguousNameOnly = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [nameOnly], source: legacySource, destination: target,
            nameOnlyCandidates: [legacySource, otherSameName, otherModule]
        )
        precondition(!ambiguousNameOnly.didChange)
        precondition(ambiguousNameOnly.hasUnresolvedNameOnlyReference)
        let reviewedIntoTarget = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [nameOnly], source: legacySource, destination: target,
            nameOnlyCandidates: [legacySource, otherSameName], nameOnlyResolution: target
        )
        precondition(reviewedIntoTarget.didChange && reviewedIntoTarget.references == [target])
        let reviewedAsOther = VerbalLegacyKnowledgePointMigrationPolicy.plan(
            references: [nameOnly], source: legacySource, destination: target,
            nameOnlyCandidates: [legacySource, otherSameName, otherModule], nameOnlyResolution: otherModule
        )
        precondition(reviewedAsOther.didChange && reviewedAsOther.references == [otherModule])
        precondition(LibraryKnowledgePointFilterPolicy.preservingAvailableSelection(
            [typeA, typeB], among: [typeB]
        ) == [typeB])
    }
}
