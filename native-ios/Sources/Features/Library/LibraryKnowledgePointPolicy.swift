import Foundation

struct LibraryKnowledgePointGroup: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var memberNames: [String]

    init(id: String = UUID().uuidString, name: String, memberNames: [String] = []) {
        self.id = id
        self.name = name
        self.memberNames = memberNames
    }
}

enum LibraryKnowledgePointGroupPolicy {
    static func scopeKey(subject: String = "", module: String, typeID: String?) -> String {
        "\(subject)\u{1f}\(module)\u{1f}\(typeID ?? "")"
    }

    static func normalizedName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func canUseGroupName(_ raw: String, groups: [LibraryKnowledgePointGroup], excluding id: String? = nil) -> Bool {
        let name = normalizedName(raw)
        return !name.isEmpty && !groups.contains { $0.id != id && normalizedName($0.name) == name }
    }

    static func addGroup(_ group: LibraryKnowledgePointGroup, to groups: [LibraryKnowledgePointGroup]) -> [LibraryKnowledgePointGroup] {
        guard canUseGroupName(group.name, groups: groups) else { return groups }
        var value = group
        value.name = normalizedName(value.name)
        return groups + [value]
    }

    static func renameGroup(_ id: String, to raw: String, in groups: [LibraryKnowledgePointGroup]) -> [LibraryKnowledgePointGroup]? {
        guard canUseGroupName(raw, groups: groups, excluding: id), groups.contains(where: { $0.id == id }) else { return nil }
        return groups.map { group in
            guard group.id == id else { return group }
            var changed = group
            changed.name = normalizedName(raw)
            return changed
        }
    }

    static func deleteGroup(_ id: String, from groups: [LibraryKnowledgePointGroup]) -> [LibraryKnowledgePointGroup] {
        groups.filter { $0.id != id }
    }

    static func assign(_ member: String, to groupID: String?, in groups: [LibraryKnowledgePointGroup]) -> [LibraryKnowledgePointGroup] {
        groups.map { group in
            var changed = group
            changed.memberNames.removeAll { $0 == member }
            if group.id == groupID { changed.memberNames.append(member) }
            return changed
        }
    }

    static func renameMember(_ old: String, to new: String?, in groups: [LibraryKnowledgePointGroup]) -> [LibraryKnowledgePointGroup] {
        groups.map { group in
            var changed = group
            changed.memberNames = changed.memberNames.compactMap { member in
                guard member == old else { return member }
                return new
            }
            var seen = Set<String>()
            changed.memberNames = changed.memberNames.filter { seen.insert($0).inserted }
            return changed
        }
    }

    static func mergedOrder(
        fullOrder: [String],
        groups: [LibraryKnowledgePointGroup],
        groupID: String?,
        displayedOrder: [String]
    ) -> [String]? {
        guard Set(fullOrder).count == fullOrder.count else { return nil }
        if groups.isEmpty {
            guard displayedOrder.count == fullOrder.count, Set(displayedOrder) == Set(fullOrder) else { return nil }
            return displayedOrder
        }

        let assigned = Set(groups.flatMap(\.memberNames))
        let targetMembers: Set<String>
        if let groupID {
            guard let group = groups.first(where: { $0.id == groupID }) else { return nil }
            targetMembers = Set(group.memberNames)
        } else {
            targetMembers = Set(fullOrder.filter { !assigned.contains($0) })
        }
        guard displayedOrder.count == targetMembers.count,
              Set(displayedOrder) == targetMembers,
              fullOrder.filter(targetMembers.contains).count == targetMembers.count else { return nil }
        var iterator = displayedOrder.makeIterator()
        return fullOrder.map { targetMembers.contains($0) ? (iterator.next() ?? $0) : $0 }
    }
}

enum LibraryKnowledgePointFilterPolicy {
    static func matches(
        recordReferences: [LibraryKnowledgePointReference],
        selectedReferences: [LibraryKnowledgePointReference]
    ) -> Bool {
        let selected = Set(selectedReferences)
        return selected.isEmpty || recordReferences.contains(where: selected.contains)
    }

    static func unique(_ references: [LibraryKnowledgePointReference]) -> [LibraryKnowledgePointReference] {
        LibraryKnowledgePointReferencePolicy.uniqueReferences(references)
    }

    static func preservingAvailableSelection(
        _ selected: [LibraryKnowledgePointReference],
        among available: [LibraryKnowledgePointReference]
    ) -> [LibraryKnowledgePointReference] {
        let availableSet = Set(available)
        return selected.filter(availableSet.contains)
    }
}
