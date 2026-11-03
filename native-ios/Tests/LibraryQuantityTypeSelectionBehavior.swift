@main
enum LibraryQuantityTypeSelectionBehavior {
    static func main() {
        let available = ["几何问题", "排列组合/概率"]
        precondition(
            LibraryQuantityTypeSelectionPolicy.concreteType(selected: "几何问题", availableTypes: available) == "几何问题",
            "a selected concrete quantity type must be passed to the new error draft's scope module"
        )
        precondition(
            LibraryQuantityTypeSelectionPolicy.concreteType(selected: "未分类", availableTypes: available) == nil,
            "the unclassified filter must not become a concrete draft type"
        )
        precondition(
            LibraryQuantityTypeSelectionPolicy.concreteType(selected: "", availableTypes: available) == nil,
            "the all-types view must leave the draft type unassigned"
        )
        precondition(
            LibraryQuantityTypeSelectionPolicy.concreteType(selected: "已移除题型", availableTypes: available) == nil,
            "a stale selection must not be persisted as a draft type"
        )
    }
}
