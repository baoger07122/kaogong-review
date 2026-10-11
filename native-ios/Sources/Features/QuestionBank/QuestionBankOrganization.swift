import Foundation
import SwiftUI

struct QuestionBankPaperGroup: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}

struct QuestionBankPaperPlacement: Codable, Equatable, Identifiable, Sendable {
    var paperID: String
    var groupID: String?
    var order: Int

    var id: String { paperID }
}

struct QuestionBankOrganizationSnapshot: Codable, Equatable, Sendable {
    var groups: [QuestionBankPaperGroup] = []
    var placements: [QuestionBankPaperPlacement] = []
}

struct QuestionBankOrganizationSection: Identifiable, Equatable, Sendable {
    static let ungroupedID = "__question_bank_ungrouped__"

    var id: String
    var groupID: String?
    var title: String
    var paperIDs: [String]
}

@MainActor
final class QuestionBankOrganizationStore: ObservableObject {
    static let appStorageKey = "question-bank.paper-organization.v1"

    @Published private(set) var snapshot: QuestionBankOrganizationSnapshot
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.appStorageKey),
           let stored = try? JSONDecoder().decode(QuestionBankOrganizationSnapshot.self, from: data) {
            snapshot = Self.normalized(stored)
        } else {
            snapshot = QuestionBankOrganizationSnapshot()
        }
    }

    func reconcile(paperIDs: [String]) {
        let validIDs = Set(paperIDs)
        var next = snapshot
        next.placements.removeAll { !validIDs.contains($0.paperID) }
        var knownIDs = Set(next.placements.map(\.paperID))
        for paperID in paperIDs where knownIDs.insert(paperID).inserted {
            next.placements.append(QuestionBankPaperPlacement(
                paperID: paperID,
                groupID: nil,
                order: next.placements.filter { $0.groupID == nil }.count
            ))
        }
        commit(Self.normalized(next))
    }

    func sections(for visiblePaperIDs: [String]) -> [QuestionBankOrganizationSection] {
        let visible = Set(visiblePaperIDs)
        var result: [QuestionBankOrganizationSection] = []
        for group in snapshot.groups {
            let paperIDs = orderedPaperIDs(in: group.id).filter(visible.contains)
            if !paperIDs.isEmpty {
                result.append(QuestionBankOrganizationSection(
                    id: group.id, groupID: group.id, title: group.name, paperIDs: paperIDs
                ))
            }
        }
        let ungrouped = orderedPaperIDs(in: nil).filter(visible.contains)
        if !ungrouped.isEmpty {
            result.append(QuestionBankOrganizationSection(
                id: QuestionBankOrganizationSection.ungroupedID,
                groupID: nil,
                title: "未分组",
                paperIDs: ungrouped
            ))
        }
        return result
    }

    func orderedPaperIDs(in groupID: String?) -> [String] {
        snapshot.placements
            .filter { $0.groupID == groupID }
            .sorted { left, right in
                if left.order != right.order { return left.order < right.order }
                return left.paperID < right.paperID
            }
            .map(\.paperID)
    }

    @discardableResult
    func addGroup(named name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !snapshot.groups.contains(where: { $0.name == normalized }) else { return false }
        var next = snapshot
        next.groups.append(QuestionBankPaperGroup(id: UUID().uuidString.lowercased(), name: normalized))
        commit(next)
        return true
    }

    @discardableResult
    func renameGroup(id: String, to name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              !snapshot.groups.contains(where: { $0.id != id && $0.name == normalized }),
              let index = snapshot.groups.firstIndex(where: { $0.id == id }) else { return false }
        var next = snapshot
        next.groups[index].name = normalized
        commit(next)
        return true
    }

    func deleteGroup(id: String) {
        var next = snapshot
        let moving = next.placements.filter { $0.groupID == id }.sorted { $0.order < $1.order }
        next.placements.removeAll { $0.groupID == id }
        var ungrouped = next.placements.filter { $0.groupID == nil }.sorted { $0.order < $1.order }
        for placement in moving {
            ungrouped.append(QuestionBankPaperPlacement(
                paperID: placement.paperID,
                groupID: nil,
                order: ungrouped.count
            ))
        }
        next.placements.removeAll { $0.groupID == nil }
        next.placements.append(contentsOf: ungrouped)
        next.groups.removeAll { $0.id == id }
        commit(next)
    }

    func moveGroup(fromOffsets: IndexSet, toOffset: Int) {
        var next = snapshot
        next.groups.move(fromOffsets: fromOffsets, toOffset: toOffset)
        commit(next)
    }

    func movePaper(_ paperID: String, to groupID: String?) {
        guard groupID == nil || snapshot.groups.contains(where: { $0.id == groupID }) else { return }
        var next = snapshot
        let previousGroupID = next.placements.first(where: { $0.paperID == paperID })?.groupID
        next.placements.removeAll { $0.paperID == paperID }
        reindexPlacements(&next.placements, in: groupID)
        if previousGroupID != groupID {
            reindexPlacements(&next.placements, in: previousGroupID)
        }
        let destinationOrder = next.placements.filter { $0.groupID == groupID }.count
        next.placements.append(QuestionBankPaperPlacement(
            paperID: paperID, groupID: groupID, order: destinationOrder
        ))
        commit(next)
    }

    func movePapers(in groupID: String?, fromOffsets: IndexSet, toOffset: Int) {
        var next = snapshot
        var ids = next.placements
            .filter { $0.groupID == groupID }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.paperID < $1.paperID
            }
            .map(\.paperID)
        ids.move(fromOffsets: fromOffsets, toOffset: toOffset)
        for index in next.placements.indices where next.placements[index].groupID == groupID {
            guard let order = ids.firstIndex(of: next.placements[index].paperID) else { continue }
            next.placements[index].order = order
        }
        commit(next)
    }

    func removePaper(_ paperID: String) {
        var next = snapshot
        next.placements.removeAll { $0.paperID == paperID }
        commit(Self.normalized(next))
    }

    func exportOrganization(for paperIDs: [String]) -> QuestionBankOrganizationSnapshot {
        let selectedIDs = Set(paperIDs)
        let selectedPlacements = snapshot.placements.filter { selectedIDs.contains($0.paperID) }
        let groupIDs = Set(selectedPlacements.compactMap(\.groupID))
        let groups = snapshot.groups.compactMap { group -> QuestionBankPaperGroup? in
            guard groupIDs.contains(group.id) else { return nil }
            return QuestionBankPaperGroup(id: group.id, name: group.name)
        }
        let orderedPlacements = selectedPlacements
            .sorted { left, right in
                let leftGroupOrder = left.groupID.flatMap { id in snapshot.groups.firstIndex(where: { $0.id == id }) } ?? Int.max
                let rightGroupOrder = right.groupID.flatMap { id in snapshot.groups.firstIndex(where: { $0.id == id }) } ?? Int.max
                if leftGroupOrder != rightGroupOrder { return leftGroupOrder < rightGroupOrder }
                if left.order != right.order { return left.order < right.order }
                return left.paperID < right.paperID
            }
        var nextOrderByGroup: [String: Int] = [:]
        var nextUngroupedOrder = 0
        let placements = orderedPlacements.map { placement in
            let order: Int
            if let groupID = placement.groupID {
                order = nextOrderByGroup[groupID, default: 0]
                nextOrderByGroup[groupID] = order + 1
            } else {
                order = nextUngroupedOrder
                nextUngroupedOrder += 1
            }
            return QuestionBankPaperPlacement(
                    paperID: placement.paperID,
                    groupID: placement.groupID,
                    order: order
            )
        }
        return QuestionBankOrganizationSnapshot(groups: groups, placements: placements)
    }

    private func commit(_ value: QuestionBankOrganizationSnapshot) {
        let normalized = Self.normalized(value)
        guard normalized != snapshot else { return }
        snapshot = normalized
        if let data = try? JSONEncoder.sorted.encode(normalized) {
            defaults.set(data, forKey: Self.appStorageKey)
        }
    }

    private func reindexPlacements(
        _ placements: inout [QuestionBankPaperPlacement],
        in groupID: String?
    ) {
        let orderedIDs = placements
            .filter { $0.groupID == groupID }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.paperID < $1.paperID
            }
            .map(\.paperID)
        for (order, paperID) in orderedIDs.enumerated() {
            if let index = placements.firstIndex(where: { $0.paperID == paperID }) {
                placements[index].order = order
            }
        }
    }

    private static func normalized(_ value: QuestionBankOrganizationSnapshot) -> QuestionBankOrganizationSnapshot {
        var result = value
        var seenGroups = Set<String>()
        result.groups = result.groups.filter { !$0.id.isEmpty && seenGroups.insert($0.id).inserted }
        let groupIDs = Set(result.groups.map(\.id))
        var seenPapers = Set<String>()
        result.placements = result.placements
            .filter { !$0.paperID.isEmpty && seenPapers.insert($0.paperID).inserted }
            .map { placement in
                var placement = placement
                if let groupID = placement.groupID, !groupIDs.contains(groupID) { placement.groupID = nil }
                return placement
            }
        for groupID in groupIDs {
            let ordered = result.placements
                .filter { $0.groupID == groupID }
                .sorted {
                    if $0.order != $1.order { return $0.order < $1.order }
                    return $0.paperID < $1.paperID
                }
            for (order, placement) in ordered.enumerated() {
                if let index = result.placements.firstIndex(where: { $0.paperID == placement.paperID }) {
                    result.placements[index].order = order
                }
            }
        }
        let ungrouped = result.placements
            .filter { $0.groupID == nil }
            .sorted {
                if $0.order != $1.order { return $0.order < $1.order }
                return $0.paperID < $1.paperID
            }
        for (order, placement) in ungrouped.enumerated() {
            if let index = result.placements.firstIndex(where: { $0.paperID == placement.paperID }) {
                result.placements[index].order = order
            }
        }
        return result
    }
}

private extension JSONEncoder {
    static var sorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}
