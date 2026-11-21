import Foundation
import SwiftData

enum LibraryKnowledgePointGroupRepository {
    static let recordID = "library_knowledge_point_groups_v1"

    static func groups(
        subject: String = "", module: String, typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord]
    ) -> [LibraryKnowledgePointGroup] {
        load(records: records)[LibraryKnowledgePointGroupPolicy.scopeKey(
            subject: subject, module: module, typeID: typeID, category: category
        )] ?? []
    }

    static func groupID(
        for tag: String,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord]
    ) -> String? {
        groups(subject: subject, module: module, typeID: typeID, category: category, records: records)
            .first(where: { $0.memberNames.contains(tag) })?.id
    }

    static func names(
        in groupID: String?,
        allNames: [String],
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        matching query: String = ""
    ) -> [String] {
        let allGroups = groups(subject: subject, module: module, typeID: typeID, category: category, records: records)
        return LibraryKnowledgePointGroupPolicy.names(
            in: groupID, allNames: allNames, groups: allGroups, matching: query
        )
    }

    static func addGroup(
        _ rawName: String,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> LibraryKnowledgePointGroup? {
        let scope = LibraryKnowledgePointGroupPolicy.scopeKey(
            subject: subject, module: module, typeID: typeID, category: category
        )
        var values = load(records: records)
        let current = values[scope] ?? []
        let name = LibraryKnowledgePointGroupPolicy.normalizedName(rawName)
        guard LibraryKnowledgePointGroupPolicy.canUseGroupName(name, groups: current) else { return nil }
        let group = LibraryKnowledgePointGroup(name: name)
        values[scope] = LibraryKnowledgePointGroupPolicy.addGroup(group, to: current)
        try persist(values, records: records, context: context)
        return group
    }

    static func renameGroup(
        _ id: String,
        to rawName: String,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext
    ) throws -> Bool {
        let scope = LibraryKnowledgePointGroupPolicy.scopeKey(
            subject: subject, module: module, typeID: typeID, category: category
        )
        var values = load(records: records)
        guard let changed = LibraryKnowledgePointGroupPolicy.renameGroup(id, to: rawName, in: values[scope] ?? []) else {
            return false
        }
        values[scope] = changed
        try persist(values, records: records, context: context)
        return true
    }

    static func deleteGroup(
        _ id: String,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext
    ) throws {
        let scope = LibraryKnowledgePointGroupPolicy.scopeKey(
            subject: subject, module: module, typeID: typeID, category: category
        )
        var values = load(records: records)
        values[scope] = LibraryKnowledgePointGroupPolicy.deleteGroup(id, from: values[scope] ?? [])
        try persist(values, records: records, context: context)
    }

    static func assign(
        _ tag: String,
        to groupID: String?,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        let scope = LibraryKnowledgePointGroupPolicy.scopeKey(
            subject: subject, module: module, typeID: typeID, category: category
        )
        var values = load(records: records)
        let groups = values[scope] ?? []
        guard groupID == nil || groups.contains(where: { $0.id == groupID }) else { return }
        values[scope] = LibraryKnowledgePointGroupPolicy.assign(tag, to: groupID, in: groups)
        try persist(values, records: records, context: context, save: shouldSave)
    }

    static func addTagToGroup(
        _ tag: String,
        groupID: String?,
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        guard let groupID else { return }
        try assign(tag, to: groupID, subject: subject, module: module, typeID: typeID, category: category, records: records,
                   context: context, save: shouldSave)
    }

    static func migrateQuantityTypeScope(
        from sourceModule: String,
        to destinationModule: String?,
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        let destinationModule = destinationModule ?? ""
        guard sourceModule != destinationModule else { return }

        var values = load(records: records)
        var changed = false
        for category in [LibraryKnowledgePointGroupCategory.knowledgePoint, .mistakeTag] {
            let sourceScope = LibraryKnowledgePointGroupPolicy.scopeKey(
                subject: "数量关系", module: sourceModule, typeID: nil, category: category
            )
            let destinationScope = LibraryKnowledgePointGroupPolicy.scopeKey(
                subject: "数量关系", module: destinationModule, typeID: nil, category: category
            )
            guard let sourceGroups = values.removeValue(forKey: sourceScope) else { continue }
            changed = true
            var destinationGroups = values[destinationScope] ?? []
            for sourceGroup in sourceGroups {
                if let index = destinationGroups.firstIndex(where: {
                    LibraryKnowledgePointGroupPolicy.normalizedName($0.name)
                        == LibraryKnowledgePointGroupPolicy.normalizedName(sourceGroup.name)
                }) {
                    var merged = destinationGroups[index]
                    merged.memberNames = uniqueNames(merged.memberNames + sourceGroup.memberNames)
                    destinationGroups[index] = merged
                } else {
                    destinationGroups.append(sourceGroup)
                }
            }
            values[destinationScope] = destinationGroups
        }

        guard changed else { return }
        try persist(values, records: records, context: context, save: shouldSave)
    }

    static func renameTagMember(
        _ oldName: String,
        to newName: String?,
        subject: String? = nil,
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        var values = load(records: records)
        let matchingScopes: [String]
        if let subject {
            matchingScopes = [LibraryKnowledgePointGroupPolicy.scopeKey(
                subject: subject, module: module, typeID: typeID, category: category
            )]
        } else {
            matchingScopes = values.keys.filter { key in
                let parts = key.components(separatedBy: "\u{1f}")
                guard parts.count >= 3, parts[1] == module else { return false }
                let keyCategory: LibraryKnowledgePointGroupCategory = parts.count >= 4
                    ? (LibraryKnowledgePointGroupCategory(rawValue: parts[3]) ?? .knowledgePoint)
                    : .knowledgePoint
                guard keyCategory == category else { return false }
                return typeID == nil || parts[2] == typeID
            }
        }
        var changed = false
        for scope in matchingScopes {
            guard let current = values[scope], current.contains(where: { $0.memberNames.contains(oldName) }) else { continue }
            values[scope] = LibraryKnowledgePointGroupPolicy.renameMember(oldName, to: newName, in: current)
            changed = true
        }
        guard changed else { return }
        try persist(values, records: records, context: context, save: shouldSave)
    }

    static func mergedOrder(
        displayedOrder: [String],
        groupID: String?,
        fullOrder: [String],
        subject: String = "",
        module: String,
        typeID: String? = nil,
        category: LibraryKnowledgePointGroupCategory = .knowledgePoint,
        records: [StoredRecord]
    ) -> [String] {
        LibraryKnowledgePointGroupPolicy.mergedOrder(
            fullOrder: fullOrder,
            groups: groups(subject: subject, module: module, typeID: typeID, category: category, records: records),
            groupID: groupID,
            displayedOrder: displayedOrder
        ) ?? fullOrder
    }

    private static func load(records: [StoredRecord]) -> [String: [LibraryKnowledgePointGroup]] {
        guard let object = records.first(where: { $0.collection == "keyvalue" && $0.recordID == recordID })?.jsonObject,
              let value = object["value"] as? [String: Any] else { return [:] }
        return value.reduce(into: [:]) { result, item in
            guard let data = try? JSONSerialization.data(withJSONObject: item.value),
                  let groups = try? JSONDecoder().decode([LibraryKnowledgePointGroup].self, from: data) else { return }
            result[item.key] = groups
        }
    }

    private static func persist(
        _ values: [String: [LibraryKnowledgePointGroup]],
        records: [StoredRecord],
        context: ModelContext,
        save shouldSave: Bool = true
    ) throws {
        let rawValue = try values.mapValues { groups in
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(groups))
        }
        let payload = try JSONSerialization.data(
            withJSONObject: ["key": recordID, "value": rawValue], options: [.sortedKeys]
        )
        let existing = records.first { $0.collection == "keyvalue" && $0.recordID == recordID }
        let before = existing.map { ($0.payload, $0.indexPayload, $0.updatedAt) }
        do {
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = .now
            } else {
                context.insert(StoredRecord(collection: "keyvalue", recordID: recordID, payload: payload, updatedAt: .now))
            }
            if shouldSave { try context.save() }
        } catch {
            if let existing, let before {
                existing.replacePayload(before.0, indexPayload: before.1)
                existing.updatedAt = before.2
            } else if existing == nil {
                let key = recordID
                let descriptor = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                    $0.collection == "keyvalue" && $0.recordID == key
                })
                for inserted in (try? context.fetch(descriptor)) ?? [] { context.delete(inserted) }
            }
            throw error
        }
    }

    private static func uniqueNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}
