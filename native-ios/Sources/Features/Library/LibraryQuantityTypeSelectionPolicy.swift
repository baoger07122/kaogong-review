import Foundation

enum LibraryQuantityTypeSelectionPolicy {
    static let unclassifiedTitle = "未分类"

    static func concreteType(selected: String, availableTypes: [String]) -> String? {
        let value = selected.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              value != unclassifiedTitle,
              availableTypes.contains(value) else { return nil }
        return value
    }
}
