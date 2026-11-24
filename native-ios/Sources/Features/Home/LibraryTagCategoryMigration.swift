import Foundation
import SwiftData

@MainActor
enum LibraryTagCategoryMigration {
    struct Scope {
        let subject: String
        let module: String
        let typeID: String?
    }

    enum Direction: Equatable {
        case toMistakeTag
        case toKnowledgePoint

        var destination: ManagedTagKind {
            self == .toMistakeTag ? .mistakeTag : .knowledgePoint
        }

        var sourceGroup: LibraryKnowledgePointGroupCategory {
            self == .toMistakeTag ? .knowledgePoint : .mistakeTag
        }
    }

    struct Preview {
        let name: String
        let scope: Scope
        let direction: Direction
        let affectedRecordIDs: Set<String>
        let destinationExists: Bool
    }

    private struct Change {
        let record: StoredRecord
        let payload: Data
    }

    private struct Snapshot {
        let record: StoredRecord
        let payload: Data
        let indexPayload: Data?
        let updatedAt: Date?

        init(_ record: StoredRecord) {
            self.record = record
            payload = record.payload
            indexPayload = record.indexPayload
            updatedAt = record.updatedAt
        }

        func restore() {
            record.replacePayload(payload, indexPayload: indexPayload)
            record.updatedAt = updatedAt
        }
    }

    private enum MigrationError: LocalizedError {
        case stale
        case ambiguous([String])
        case sharedLegacyModule

        var errorDescription: String? {
            switch self {
            case .stale:
                "标签目录或关联错题已变化，请重新选择标签。"
            case .ambiguous(let titles):
                "有 \(titles.count) 道错题只保存了标签名称，当前模块存在同名考点。请在错题里重新选择正确的考点再迁移。\n\(titles.prefix(4).joined(separator: "\n"))"
            case .sharedLegacyModule:
                "这个旧考点目录的模块名称在多个科目中共用。请先处理重名模块或将该标签归到具体题型，再迁移类别。"
            }
        }
    }

    static func preview(
        name: String, scope: Scope, direction: Direction, records: [StoredRecord]
    ) throws -> Preview {
        try prepare(name: name, scope: scope, direction: direction, records: records).preview
    }

    static func move(_ confirmed: Preview, records: [StoredRecord], context: ModelContext) throws -> Int {
        let plan = try prepare(name: confirmed.name, scope: confirmed.scope, direction: confirmed.direction, records: records)
        guard plan.preview.affectedRecordIDs == confirmed.affectedRecordIDs,
              plan.preview.destinationExists == confirmed.destinationExists else { throw MigrationError.stale }

        let scope = confirmed.scope
        let knowledgeCatalogID = scope.typeID == nil
            ? ManagedTagKind.knowledgePoint.recordID
            : VerbalReasoningKnowledgePointRepository.recordID(for: scope.subject)
        let catalogIDs = [knowledgeCatalogID, LibraryMistakeTagRepository.recordID, LibraryKnowledgePointGroupRepository.recordID]
        let existingCatalogs = records.filter { $0.collection == "keyvalue" && catalogIDs.contains($0.recordID) }
        let missingCatalogIDs = Set(catalogIDs).subtracting(existingCatalogs.map(\.recordID))
        let snapshots = (existingCatalogs + plan.changes.map(\.record)).map(Snapshot.init)
        let now = Date.now
        do {
            try context.transaction {
                let movesToKnowledgePoint = confirmed.direction == .toKnowledgePoint
                if let typeID = scope.typeID {
                    try VerbalReasoningKnowledgePointRepository.stageKnowledgePointMembership(
                        confirmed.name, subject: scope.subject, module: scope.module, typeID: typeID,
                        isPresent: movesToKnowledgePoint, records: records, context: context
                    )
                } else {
                    try TagLibraryRepository.stageKnowledgePointMembership(
                        confirmed.name, module: scope.module, isPresent: movesToKnowledgePoint,
                        records: records, context: context
                    )
                }
                try LibraryMistakeTagRepository.stageMembership(
                    confirmed.name, subject: scope.subject, module: scope.module, typeID: scope.typeID,
                    isPresent: !movesToKnowledgePoint, records: records, context: context
                )
                try LibraryKnowledgePointGroupRepository.renameTagMember(
                    confirmed.name, to: nil, subject: scope.subject, module: scope.module, typeID: scope.typeID,
                    category: confirmed.direction.sourceGroup, records: records, context: context, save: false
                )
                for change in plan.changes {
                    change.record.replacePayload(change.payload)
                    change.record.updatedAt = now
                }
            }
        } catch {
            snapshots.forEach { $0.restore() }
            for key in missingCatalogIDs {
                let query = FetchDescriptor<StoredRecord>(predicate: #Predicate {
                    $0.collection == "keyvalue" && $0.recordID == key
                })
                for inserted in (try? context.fetch(query)) ?? [] { context.delete(inserted) }
            }
            throw error
        }
        return plan.changes.count
    }

    private static func prepare(
        name: String, scope: Scope, direction: Direction, records: [StoredRecord]
    ) throws -> (preview: Preview, changes: [Change]) {
        if scope.typeID == nil, SubjectDefinition.all.contains(where: { subject in
            guard subject.name != scope.subject else { return false }
            let modules = subject.isFlat ? QuantityQuestionTypeRepository.types(records: records) : subject.modules
            return modules.contains(scope.module)
        }) { throw MigrationError.sharedLegacyModule }
        let reference = LibraryKnowledgePointReference(module: scope.module, typeID: scope.typeID, name: name)
        let knowledgeNames = scope.typeID.map {
            VerbalReasoningKnowledgePointRepository.tags(module: scope.module, typeID: $0, records: records, subject: scope.subject)
        } ?? TagLibraryRepository.tags(kind: .knowledgePoint, module: scope.module, records: records)
        let mistakeNames = LibraryMistakeTagRepository.tags(
            subject: scope.subject, module: scope.module, typeID: scope.typeID, records: records
        )
        let movesToMistakeTag = direction == .toMistakeTag
        guard (movesToMistakeTag ? knowledgeNames : mistakeNames).contains(name) else { throw MigrationError.stale }

        let destinationExists = (movesToMistakeTag ? mistakeNames : knowledgeNames).contains(name)
        let knownNames = VerbalReasoningKnowledgePointRepository.knownNames(records: records, subject: scope.subject).union([name])
        let localCandidates = VerbalReasoningKnowledgePointRepository.nameOnlyCandidates(
            name: name, source: reference, records: records, subject: scope.subject
        ).filter { $0.module == scope.module }
        var changes: [Change] = []
        var ambiguousTitles: [String] = []
        for record in records where record.collection == "errors" {
            guard let index = record.indexObject,
                  field("subject", in: index, fallback: record.subject) == scope.subject,
                  var object = record.jsonObject else { continue }
            let isLocalModule = field("module", in: object, fallback: record.module ?? index["module"] as? String) == scope.module
            let plan = LibraryTagCategoryReferencePolicy.plan(
                knowledge: LibraryKnowledgePointReferencePolicy.references(from: object, knownNames: knownNames),
                mistakes: LibraryMistakeTagPolicy.references(from: object),
                tag: reference, toMistakeTag: movesToMistakeTag, isLocalModule: isLocalModule,
                localKnowledgeCandidates: localCandidates, destinationExists: destinationExists
            )
            switch plan {
            case .unchanged:
                continue
            case .ambiguous:
                ambiguousTitles.append(String(record.title.prefix(45)))
            case .moved(let knowledge, let mistakes):
                let names = LibraryKnowledgePointReferencePolicy.displayNames(from: knowledge)
                object["knowledgePointRefs"] = knowledge.map(\.jsonValue)
                object["knowledgePoints"] = names
                object["knowledgePoint"] = names.joined(separator: "、")
                object["mistakeTagRefs"] = mistakes.map(\.jsonValue)
                let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                changes.append(Change(record: record, payload: payload))
            }
        }
        guard ambiguousTitles.isEmpty else { throw MigrationError.ambiguous(ambiguousTitles) }
        return (
            Preview(
                name: name, scope: scope, direction: direction,
                affectedRecordIDs: Set(changes.map { $0.record.compoundID }), destinationExists: destinationExists
            ),
            changes
        )
    }

    private static func field(_ key: String, in object: [String: Any], fallback: String?) -> String? {
        let value = (object[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return value?.isEmpty == false ? value : fallback
    }
}
