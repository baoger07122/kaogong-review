import Foundation

@main
struct KnowledgePointNameSorterBehavior {
    static func main() {
        let input = ["果实10", "果实2", "香蕉", "苹果", "蓝莓", "Apple", "apple", "A10", "A2"]
        let sorted = KnowledgePointNameSorter.sorted(input)
        expect(sorted == ["A2", "A10", "Apple", "apple", "果实2", "果实10", "蓝莓", "苹果", "香蕉"],
            "English names compare without case, numbers compare naturally, and Chinese uses pinyin")
        expect(KnowledgePointNameSorter.sorted(["同名", "同名"]) == ["同名", "同名"],
            "equal names keep a stable order")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}
