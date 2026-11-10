import Foundation

enum KnowledgePointNameSorter {
    static func sorted(_ values: [String]) -> [String] {
        values.enumerated().sorted { left, right in
            let leftKey = sortKey(left.element)
            let rightKey = sortKey(right.element)
            let comparison = (leftKey as NSString).compare(
                rightKey,
                options: [.numeric, .caseInsensitive]
            )
            if comparison != .orderedSame { return comparison == .orderedAscending }

            let originalComparison = (left.element as NSString).compare(
                right.element,
                options: [.numeric, .caseInsensitive]
            )
            if originalComparison != .orderedSame { return originalComparison == .orderedAscending }
            return left.offset < right.offset
        }.map(\.element)
    }

    private static func sortKey(_ value: String) -> String {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let latin = normalized.applyingTransform(.toLatin, reverse: false) ?? normalized
        let unaccented = latin.applyingTransform(.stripCombiningMarks, reverse: false) ?? latin
        return unaccented.lowercased()
    }
}
