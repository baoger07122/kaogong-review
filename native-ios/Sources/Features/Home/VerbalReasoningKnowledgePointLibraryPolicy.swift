import Foundation

enum VerbalReasoningKnowledgePointLibraryPolicy {
    static func tags(from library: [String: Any]?, module: String, typeID: String) -> [String] {
        guard let moduleValue = library?[module] as? [String: Any] else { return [] }
        return moduleValue[typeID] as? [String] ?? []
    }

    static func replacingTags(
        _ tags: [String],
        in library: [String: Any],
        module: String,
        typeID: String
    ) -> [String: Any] {
        var modules = library
        var groups = modules[module] as? [String: Any] ?? [:]
        groups[typeID] = tags
        modules[module] = groups
        return modules
    }
}
