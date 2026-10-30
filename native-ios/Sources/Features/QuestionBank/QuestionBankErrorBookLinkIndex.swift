import Foundation
import OSLog
import SwiftData

struct QuestionBankErrorBookLinkKey: Hashable, Sendable {
    let paperID: String
    let questionID: String
}

struct QuestionBankErrorBookLinkResolution: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case linked(recordID: String)
        case unlinked
        case identityConflict(recordID: String)
    }

    let state: State
    let candidateRecordIDs: [String]
}

private struct QuestionBankErrorBookLegacyEntry: Sendable {
    let key: QuestionBankErrorBookLinkKey
    let recordID: String
}

private struct QuestionBankErrorBookLegacyIndexResult: Sendable {
    let entries: [QuestionBankErrorBookLegacyEntry]
    let recordCount: Int
    let inspectedPayloadBytes: Int
    let elapsedMilliseconds: Double
}

private struct QuestionBankErrorBookLegacyRecordRow: Sendable {
    let compoundID: String
    let recordID: String
    let indexPayload: Data?
    let payload: Data

    init(_ record: StoredRecord) {
        compoundID = record.compoundID
        recordID = record.recordID
        indexPayload = record.indexPayload
        payload = record.payload
    }
}

private struct QuestionBankErrorBookPayloadLink: Sendable {
    let paperID: String?
    let questionID: String?
    let inspectedPayloadBytes: Int

    var completeKey: QuestionBankErrorBookLinkKey? {
        guard let paperID, !paperID.isEmpty, let questionID, !questionID.isEmpty else { return nil }
        return QuestionBankErrorBookLinkKey(paperID: paperID, questionID: questionID)
    }
}

private enum QuestionBankErrorBookPayloadLinkParser {
    private static let paperKey = Data("\"questionBankPaperID\"".utf8)
    private static let questionKey = Data("\"questionBankQuestionID\"".utf8)

    static func parse(indexPayload: Data?, payload: Data) -> QuestionBankErrorBookPayloadLink {
        var inspectedBytes = 0
        if let indexPayload, containsLinkKey(indexPayload) {
            inspectedBytes += indexPayload.count
            if let indexed = decode(indexPayload), indexed.completeKey != nil {
                return QuestionBankErrorBookPayloadLink(
                    paperID: indexed.paperID,
                    questionID: indexed.questionID,
                    inspectedPayloadBytes: inspectedBytes
                )
            }
        }
        guard containsLinkKey(payload) else {
            return QuestionBankErrorBookPayloadLink(
                paperID: nil,
                questionID: nil,
                inspectedPayloadBytes: inspectedBytes
            )
        }
        inspectedBytes += payload.count
        guard let decoded = decode(payload) else {
            return QuestionBankErrorBookPayloadLink(
                paperID: nil,
                questionID: nil,
                inspectedPayloadBytes: inspectedBytes
            )
        }
        return QuestionBankErrorBookPayloadLink(
            paperID: decoded.paperID,
            questionID: decoded.questionID,
            inspectedPayloadBytes: inspectedBytes
        )
    }

    private static func containsLinkKey(_ data: Data) -> Bool {
        data.range(of: paperKey) != nil || data.range(of: questionKey) != nil
    }

    private static func decode(_ data: Data) -> QuestionBankErrorBookPayloadLink? {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return QuestionBankErrorBookPayloadLink(
            paperID: object["questionBankPaperID"] as? String,
            questionID: object["questionBankQuestionID"] as? String,
            inspectedPayloadBytes: 0
        )
    }
}

private struct QuestionBankErrorBookCandidate: Sendable {
    let recordID: String
    let paperID: String?
    let questionID: String?
}

private struct QuestionBankErrorBookCachedResolution {
    let linkedIDsSignature: String
    let resolution: QuestionBankErrorBookLinkResolution
    let legacyCompatibilityChecked: Bool
}

private struct QuestionBankErrorBookLegacyIndexFlight {
    let id: UUID
    let task: Task<QuestionBankErrorBookLegacyIndexResult, Error>
    var waiterCount: Int
}

private final class QuestionBankErrorBookLegacyIndexWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var didRelease = false

    func claimRelease() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didRelease else { return false }
        didRelease = true
        return true
    }
}

private enum QuestionBankErrorBookLegacyIndexBuilder {
    private static let chunkSize = 128

    static func load(container: ModelContainer) throws -> QuestionBankErrorBookLegacyIndexResult {
        let startedAt = ProcessInfo.processInfo.systemUptime
        let collection = LibraryContentKind.errors.collection
        var entries: [QuestionBankErrorBookLegacyEntry] = []
        var inspectedPayloadBytes = 0
        var recordCount = 0
        var cursor: String?

        while true {
            guard !Task.isCancelled else { throw CancellationError() }
            let rows = try fetchPage(container: container, collection: collection, cursor: cursor)
            guard !Task.isCancelled else { throw CancellationError() }
            guard !rows.isEmpty else { break }
            recordCount += rows.count
            cursor = rows.last?.compoundID

            for row in rows {
                guard !Task.isCancelled else { throw CancellationError() }
                let link = QuestionBankErrorBookPayloadLinkParser.parse(
                    indexPayload: row.indexPayload,
                    payload: row.payload
                )
                inspectedPayloadBytes += link.inspectedPayloadBytes
                guard let key = link.completeKey else { continue }
                entries.append(QuestionBankErrorBookLegacyEntry(key: key, recordID: row.recordID))
            }
            if rows.count < chunkSize { break }
        }

        return QuestionBankErrorBookLegacyIndexResult(
            entries: entries,
            recordCount: recordCount,
            inspectedPayloadBytes: inspectedPayloadBytes,
            elapsedMilliseconds: (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        )
    }

    private static func fetchPage(
        container: ModelContainer,
        collection: String,
        cursor: String?
    ) throws -> [QuestionBankErrorBookLegacyRecordRow] {
        let context = ModelContext(container)
        let descriptor: FetchDescriptor<StoredRecord>
        if let cursor {
            let lastCompoundID = cursor
            let predicate = #Predicate<StoredRecord> {
                $0.collection == collection && $0.compoundID > lastCompoundID
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\StoredRecord.compoundID, order: .forward)]
            )
        } else {
            let predicate = #Predicate<StoredRecord> { $0.collection == collection }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\StoredRecord.compoundID, order: .forward)]
            )
        }
        var pageDescriptor = descriptor
        pageDescriptor.fetchLimit = chunkSize
        return try context.fetch(pageDescriptor).map(QuestionBankErrorBookLegacyRecordRow.init)
    }
}

actor QuestionBankErrorBookLinkIndex {
    static let shared = QuestionBankErrorBookLinkIndex()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.baoger07122.kaogongreview.nativebeta",
        category: "question-bank-error-links"
    )
    private var legacyLinksByContainer: [ObjectIdentifier: [QuestionBankErrorBookLinkKey: [String]]] = [:]
    private var legacyIndexFlights: [ObjectIdentifier: QuestionBankErrorBookLegacyIndexFlight] = [:]
    private var resolutionsByContainer: [ObjectIdentifier: [QuestionBankErrorBookLinkKey: QuestionBankErrorBookCachedResolution]] = [:]

    func resolve(
        question: QuestionBankQuestion,
        container: ModelContainer
    ) async throws -> QuestionBankErrorBookLinkResolution {
        try Task.checkCancellation()
        let containerID = ObjectIdentifier(container)
        let key = QuestionBankErrorBookLinkKey(paperID: question.paperID, questionID: question.id)
        let linkedIDs = question.linkedErrorRecordIDs ?? []
        let signature = linkedIDs.sorted().joined(separator: "\u{1f}")
        let deterministicIDs = Set(QuestionBankErrorBookCategory.allCases.map {
            QuestionBankErrorBookIdentity.recordID(
                paperID: question.paperID,
                questionID: question.id,
                category: $0
            )
        })
        let directIDs = Array(Set(linkedIDs).union(deterministicIDs)).sorted()
        var directCandidates: [QuestionBankErrorBookCandidate]
        if let cached = resolutionsByContainer[containerID]?[key],
           cached.linkedIDsSignature == signature {
            let candidates = try await fetchCandidates(
                recordIDs: cached.resolution.candidateRecordIDs,
                container: container,
                paperID: question.paperID,
                questionID: question.id,
                stage: "cached-revalidate"
            )
            try Task.checkCancellation()
            let revalidated = Self.resolution(
                for: candidates,
                question: question,
                deterministicIDs: deterministicIDs,
                explicitIDs: Set(linkedIDs),
                candidateIDs: cached.resolution.candidateRecordIDs
            ) ?? QuestionBankErrorBookLinkResolution(
                state: .unlinked,
                candidateRecordIDs: cached.resolution.candidateRecordIDs
            )
            if revalidated.state != .unlinked || cached.legacyCompatibilityChecked {
                return cache(
                    revalidated,
                    key: key,
                    signature: signature,
                    containerID: containerID,
                    legacyCompatibilityChecked: cached.legacyCompatibilityChecked
                )
            }
            directCandidates = candidates
        } else {
            directCandidates = try await fetchCandidates(
                recordIDs: directIDs,
                container: container,
                paperID: question.paperID,
                questionID: question.id,
                stage: "direct"
            )
            try Task.checkCancellation()
        }

        if let directResolution = Self.resolution(
            for: directCandidates,
            question: question,
            deterministicIDs: deterministicIDs,
            explicitIDs: Set(linkedIDs),
            candidateIDs: directIDs
        ), directResolution.state != .unlinked {
            return cache(
                directResolution,
                key: key,
                signature: signature,
                containerID: containerID,
                legacyCompatibilityChecked: false
            )
        }

        let legacyIDs = try await legacyRecordIDs(for: key, container: container, containerID: containerID)
        try Task.checkCancellation()
        let directIDSet = Set(directIDs)
        let additionalIDs = legacyIDs.filter { !directIDSet.contains($0) }
        let legacyCandidates = try await fetchCandidates(
            recordIDs: additionalIDs,
            container: container,
            paperID: question.paperID,
            questionID: question.id,
            stage: "legacy-candidates"
        )
        try Task.checkCancellation()

        let allCandidates = directCandidates + legacyCandidates
        let candidateIDs = Array(Set(directIDs + legacyIDs)).sorted()
        let resolution = Self.resolution(
            for: allCandidates,
            question: question,
            deterministicIDs: deterministicIDs,
            explicitIDs: Set(linkedIDs),
            candidateIDs: candidateIDs
        ) ?? QuestionBankErrorBookLinkResolution(state: .unlinked, candidateRecordIDs: candidateIDs)
        return cache(
            resolution,
            key: key,
            signature: signature,
            containerID: containerID,
            legacyCompatibilityChecked: true
        )
    }

    func invalidateResolution(paperID: String, questionID: String, container: ModelContainer) {
        let containerID = ObjectIdentifier(container)
        resolutionsByContainer[containerID]?[QuestionBankErrorBookLinkKey(paperID: paperID, questionID: questionID)] = nil
    }

    private func cache(
        _ resolution: QuestionBankErrorBookLinkResolution,
        key: QuestionBankErrorBookLinkKey,
        signature: String,
        containerID: ObjectIdentifier,
        legacyCompatibilityChecked: Bool
    ) -> QuestionBankErrorBookLinkResolution {
        resolutionsByContainer[containerID, default: [:]][key] = QuestionBankErrorBookCachedResolution(
            linkedIDsSignature: signature,
            resolution: resolution,
            legacyCompatibilityChecked: legacyCompatibilityChecked
        )
        return resolution
    }

    private static func resolution(
        for candidates: [QuestionBankErrorBookCandidate],
        question: QuestionBankQuestion,
        deterministicIDs: Set<String>,
        explicitIDs: Set<String>,
        candidateIDs: [String]? = nil
    ) -> QuestionBankErrorBookLinkResolution? {
        let matching = candidates.first { candidate in
            if candidate.paperID == question.paperID, candidate.questionID == question.id { return true }
            let paperMismatch = candidate.paperID.map { $0 != question.paperID } ?? false
            let questionMismatch = candidate.questionID.map { $0 != question.id } ?? false
            return explicitIDs.contains(candidate.recordID) && !paperMismatch && !questionMismatch
        }
        let identityConflict = candidates.first {
            deterministicIDs.contains($0.recordID)
                && !($0.paperID == question.paperID && $0.questionID == question.id)
        }
        let state: QuestionBankErrorBookLinkResolution.State
        if let matching {
            state = .linked(recordID: matching.recordID)
        } else if let identityConflict {
            state = .identityConflict(recordID: identityConflict.recordID)
        } else {
            state = .unlinked
        }
        guard state != .unlinked || candidateIDs != nil else { return nil }
        return QuestionBankErrorBookLinkResolution(
            state: state,
            candidateRecordIDs: candidateIDs ?? Array(Set(candidates.map(\.recordID))).sorted()
        )
    }

    private func fetchCandidates(
        recordIDs: [String],
        container: ModelContainer,
        paperID: String,
        questionID: String,
        stage: String
    ) async throws -> [QuestionBankErrorBookCandidate] {
        guard !recordIDs.isEmpty else { return [] }
        let startedAt = ProcessInfo.processInfo.systemUptime
        let collection = LibraryContentKind.errors.collection
        let task = Task.detached(priority: .utility) {
            let context = ModelContext(container)
            let predicate = #Predicate<StoredRecord> {
                $0.collection == collection && recordIDs.contains($0.recordID)
            }
            var descriptor = FetchDescriptor<StoredRecord>(predicate: predicate)
            descriptor.fetchLimit = recordIDs.count
            let records = try context.fetch(descriptor)
            var candidates: [QuestionBankErrorBookCandidate] = []
            candidates.reserveCapacity(records.count)
            var inspectedBytes = 0
            for record in records {
                guard !Task.isCancelled else { throw CancellationError() }
                let link = QuestionBankErrorBookPayloadLinkParser.parse(
                    indexPayload: record.indexPayload,
                    payload: record.payload
                )
                inspectedBytes += link.inspectedPayloadBytes
                candidates.append(
                    QuestionBankErrorBookCandidate(
                        recordID: record.recordID,
                        paperID: link.paperID,
                        questionID: link.questionID
                    )
                )
            }
            return (candidates, inspectedBytes, records.count)
        }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - startedAt) * 1_000
        logger.info("link stage=\(stage, privacy: .public) paper=\(paperID, privacy: .private(mask: .hash)) question=\(questionID, privacy: .private(mask: .hash)) candidates=\(recordIDs.count, privacy: .public) found=\(result.2, privacy: .public) inspectedBytes=\(result.1, privacy: .public) elapsedMs=\(elapsedMilliseconds, format: .fixed(precision: 1))")
        return result.0
    }

    private func legacyRecordIDs(
        for key: QuestionBankErrorBookLinkKey,
        container: ModelContainer,
        containerID: ObjectIdentifier
    ) async throws -> [String] {
        if let links = legacyLinksByContainer[containerID] { return links[key] ?? [] }

        let flightID: UUID
        let task: Task<QuestionBankErrorBookLegacyIndexResult, Error>
        if var flight = legacyIndexFlights[containerID] {
            flight.waiterCount += 1
            legacyIndexFlights[containerID] = flight
            flightID = flight.id
            task = flight.task
        } else {
            let id = UUID()
            let newTask = Task.detached(priority: .utility) {
                try QuestionBankErrorBookLegacyIndexBuilder.load(container: container)
            }
            legacyIndexFlights[containerID] = QuestionBankErrorBookLegacyIndexFlight(
                id: id,
                task: newTask,
                waiterCount: 1
            )
            flightID = id
            task = newTask
        }

        let waiter = QuestionBankErrorBookLegacyIndexWaiter()
        do {
            let result = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                Task { await self.releaseLegacyIndexWaiter(containerID, flightID: flightID, waiter: waiter, cancelWhenUnused: true) }
            }
            try Task.checkCancellation()
            guard legacyIndexFlights[containerID]?.id == flightID else { throw CancellationError() }
            if legacyLinksByContainer[containerID] == nil {
                var links: [QuestionBankErrorBookLinkKey: Set<String>] = [:]
                for entry in result.entries {
                    links[entry.key, default: []].insert(entry.recordID)
                }
                legacyLinksByContainer[containerID] = links.mapValues { $0.sorted() }
                logger.info("link stage=legacy-index records=\(result.recordCount, privacy: .public) linkedQuestions=\(links.count, privacy: .public) links=\(result.entries.count, privacy: .public) inspectedPayloadBytes=\(result.inspectedPayloadBytes, privacy: .public) elapsedMs=\(result.elapsedMilliseconds, format: .fixed(precision: 1)) chunkSize=128")
            }
            let ids = legacyLinksByContainer[containerID]?[key] ?? []
            releaseLegacyIndexWaiter(containerID, flightID: flightID, waiter: waiter, cancelWhenUnused: false)
            return ids
        } catch {
            releaseLegacyIndexWaiter(containerID, flightID: flightID, waiter: waiter, cancelWhenUnused: true)
            throw error
        }
    }

    private func releaseLegacyIndexWaiter(
        _ containerID: ObjectIdentifier,
        flightID: UUID,
        waiter: QuestionBankErrorBookLegacyIndexWaiter,
        cancelWhenUnused: Bool
    ) {
        guard waiter.claimRelease(), var flight = legacyIndexFlights[containerID], flight.id == flightID else { return }
        flight.waiterCount -= 1
        if flight.waiterCount <= 0 {
            if cancelWhenUnused { flight.task.cancel() }
            legacyIndexFlights[containerID] = nil
        } else {
            legacyIndexFlights[containerID] = flight
        }
    }
}
