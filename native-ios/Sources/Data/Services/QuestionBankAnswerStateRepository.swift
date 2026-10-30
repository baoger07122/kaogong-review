import CryptoKit
import Combine
import Foundation
import SwiftData

enum QuestionBankAnswerStateRepositoryError: LocalizedError {
    case mutationInProgress
    case invalidCompoundID(String)
    case invalidLegacyPayload(String)
    case ambiguousLegacyQuestionID(String)

    var errorDescription: String? {
        switch self {
        case .mutationInProgress: return "作答状态正在统一写入，请稍后重试。"
        case let .invalidCompoundID(id): return "作答状态题目 ID 无效：\(id)"
        case let .invalidLegacyPayload(message): return "旧作答数据无法读取：\(message)"
        case let .ambiguousLegacyQuestionID(id): return "旧作答数据中的题目 ID 无法唯一匹配：\(id)"
        }
    }
}

actor QuestionBankAnswerStateMutationCoordinator {
    static let shared = QuestionBankAnswerStateMutationCoordinator()

    private var isHeld = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func withExclusive<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await acquire()
        do {
            let result = try await operation()
            release()
            return result
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if !isHeld {
            isHeld = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            isHeld = false
        } else {
            waiters.removeFirst().resume()
        }
    }
}

enum QuestionBankAnswerStateRepository {
    static let batchSize = 128
    static let clearAllMigrationID = "question-bank-answer-state-clear-all-v1"
    static let changeNotification = Notification.Name("QuestionBankAnswerStateDidChange")
    static let changedIDsKey = "compoundIDs"
    static let resetKey = "reset"
    static let clearedKey = "cleared"

    static func read(
        compoundIDs: [String],
        from container: ModelContainer
    ) async throws -> [String: QuestionBankAnswerStateValue] {
        let uniqueIDs = Array(Set(compoundIDs)).sorted()
        guard !uniqueIDs.isEmpty else { return [:] }
        return try await Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            var result: [String: QuestionBankAnswerStateValue] = [:]
            for start in stride(from: 0, to: uniqueIDs.count, by: batchSize) {
                let page = Array(uniqueIDs[start..<min(start + batchSize, uniqueIDs.count)])
                let descriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                    predicate: #Predicate { page.contains($0.compoundID) }
                )
                for record in try context.fetch(descriptor) {
                    result[record.compoundID] = QuestionBankAnswerStateValue(record: record)
                }
            }
            return result
        }.value
    }

    static func readAllForBackup(from container: ModelContainer) async throws -> [QuestionBankAnswerStateBackup] {
        return try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .utility) {
                let context = ModelContext(container)
                let descriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                    sortBy: [SortDescriptor(\.compoundID)]
                )
                return try context.fetch(descriptor).map(QuestionBankAnswerStateBackup.init(record:))
            }.value
        }
    }

    static func upsert(
        _ value: QuestionBankAnswerStateValue,
        in container: ModelContainer
    ) async throws {
        guard value.compoundID == "\(value.paperID)::\(QuestionBankRepository.questionKind)::\(value.questionID)",
              !value.isCleared || (value.selectedOptionID == nil && !value.isRevealed) else {
            throw LegacyBackupImportError.invalidQuestionBankAnswerState(0)
        }
        let compoundID = value.compoundID
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                try context.transaction {
                    let barrierID = clearAllMigrationID
                    let barrierDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                        predicate: #Predicate { $0.migrationID == barrierID }
                    )
                    if let barrier = try context.fetch(barrierDescriptor).first,
                       (barrier.sourceKind == "backupRestore" || barrier.sourceKind == "clearAll"),
                       barrier.updatedAt > value.updatedAt {
                        return
                    }
                    let paperMarkerID = paperClearMarkerID(value.paperID)
                    let paperMarkerDescriptor = FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>(
                        predicate: #Predicate { $0.scopeID == paperMarkerID }
                    )
                    if let marker = try context.fetch(paperMarkerDescriptor).first,
                       marker.updatedAt > value.updatedAt {
                        return
                    }
                    let descriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                        predicate: #Predicate { $0.compoundID == compoundID }
                    )
                    if let record = try context.fetch(descriptor).first {
                        record.paperID = value.paperID
                        record.questionID = value.questionID
                        record.selectedOptionID = value.selectedOptionID
                        record.isRevealed = value.isRevealed
                        record.isCleared = value.isCleared
                        record.mutationRevision = max(record.mutationRevision + 1, value.mutationRevision)
                        record.updatedAt = .now
                    } else {
                        context.insert(QuestionBankAnswerStateRecord(
                            compoundID: value.compoundID,
                            paperID: value.paperID,
                            questionID: value.questionID,
                            selectedOptionID: value.selectedOptionID,
                            isRevealed: value.isRevealed,
                            isCleared: value.isCleared,
                            mutationRevision: max(1, value.mutationRevision),
                            updatedAt: .now
                        ))
                    }
                }
            }.value
        }
        postChange(ids: [value.compoundID])
    }

    static func clear(
        compoundIDs: [String],
        paperScope: String? = nil,
        in container: ModelContainer
    ) async throws {
        let values = try compoundIDs.map { id -> QuestionBankAnswerStateValue in
            guard let value = QuestionBankAnswerStateValue.empty(compoundID: id) else {
                throw QuestionBankAnswerStateRepositoryError.invalidCompoundID(id)
            }
            return value
        }
        guard !values.isEmpty else { return }
        let requestedAt = Date.now
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                let sorted = values.sorted { $0.compoundID < $1.compoundID }
                for start in stride(from: 0, to: sorted.count, by: batchSize) {
                    let page = Array(sorted[start..<min(start + batchSize, sorted.count)])
                    let pageIDs = page.map(\.compoundID)
                    try context.transaction {
                        let barrierID = clearAllMigrationID
                        let barrierDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                            predicate: #Predicate { $0.migrationID == barrierID }
                        )
                        if let barrier = try context.fetch(barrierDescriptor).first,
                           (barrier.sourceKind == "backupRestore" || barrier.sourceKind == "clearAll"),
                           barrier.updatedAt > requestedAt {
                            return
                        }
                        if let paperScope {
                            let markerID = paperClearMarkerID(paperScope)
                            let markerDescriptor = FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>(
                                predicate: #Predicate { $0.scopeID == markerID }
                            )
                            if let marker = try context.fetch(markerDescriptor).first {
                                marker.updatedAt = requestedAt
                            } else {
                                context.insert(QuestionBankAnswerStateScopeClearRecord(
                                    scopeID: markerID,
                                    paperID: paperScope,
                                    updatedAt: requestedAt
                                ))
                            }
                        }
                        let descriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                            predicate: #Predicate { pageIDs.contains($0.compoundID) }
                        )
                        let existing = try context.fetch(descriptor)
                        let existingByID = Dictionary(uniqueKeysWithValues: existing.map { ($0.compoundID, $0) })
                        for value in page {
                            if let record = existingByID[value.compoundID] {
                                record.selectedOptionID = nil
                                record.isRevealed = false
                                record.isCleared = true
                                record.mutationRevision += 1
                                record.updatedAt = .now
                            } else {
                                context.insert(QuestionBankAnswerStateRecord(
                                    compoundID: value.compoundID,
                                    paperID: value.paperID,
                                    questionID: value.questionID,
                                    isCleared: true
                                ))
                            }
                        }
                    }
                }
            }.value
        }
        postChange(ids: values.map(\.compoundID), cleared: true)
    }

    static func clearAllForDataReset(in container: ModelContainer) async throws {
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                try context.transaction { try clearAllForDataReset(in: context) }
            }.value
        }
        postChange(ids: [], reset: true)
    }

    static func clearAllLocalData(in container: ModelContainer) async throws {
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                try context.transaction {
                    for record in try context.fetch(FetchDescriptor<StoredRecord>()) {
                        context.delete(record)
                    }
                    try clearAllForDataReset(in: context)
                }
            }.value
        }
        postChange(ids: [], reset: true)
    }

    static func clearAllForDataReset(in context: ModelContext) throws {
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateMigrationRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>()) {
            context.delete(record)
        }
        context.insert(QuestionBankAnswerStateMigrationRecord(
            migrationID: clearAllMigrationID,
            sourceKind: "clearAll",
            sourceBackupPayload: Data(),
            sourceDigest: digest(Data()),
            phaseRawValue: "complete"
        ))
    }

    static func postReset() {
        postChange(ids: [], reset: true)
    }

    static func replaceFromBackup(
        _ values: [QuestionBankAnswerStateBackup],
        in container: ModelContainer
    ) async throws {
        let sorted = try validatedBackupValues(values)
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .userInitiated) {
                let context = ModelContext(container)
                try context.transaction {
                    for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>()) {
                        context.delete(record)
                    }
                    for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateMigrationRecord>()) {
                        context.delete(record)
                    }
                    for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>()) {
                        context.delete(record)
                    }
                    for value in sorted {
                        context.insert(QuestionBankAnswerStateRecord(
                            compoundID: value.compoundID,
                            paperID: value.paperID,
                            questionID: value.questionID,
                            selectedOptionID: value.selectedOptionID,
                            isRevealed: value.isRevealed,
                            isCleared: value.isCleared,
                            mutationRevision: value.mutationRevision,
                            updatedAt: value.updatedAt
                        ))
                    }
                    // A restore is authoritative. Old UserDefaults or SceneStorage values must not
                    // be imported after it, including when the backup is from the pre-table format.
                    context.insert(QuestionBankAnswerStateMigrationRecord(
                        migrationID: clearAllMigrationID,
                        sourceKind: "backupRestore",
                        sourceBackupPayload: Data(),
                        sourceDigest: digest(Data()),
                        phaseRawValue: "complete"
                    ))
                }
            }.value
        }
        postChange(ids: sorted.map(\.compoundID), reset: true)
    }

    static func replaceFromBackup(
        _ values: [QuestionBankAnswerStateBackup],
        in context: ModelContext
    ) throws {
        let sorted = try validatedBackupValues(values)
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateMigrationRecord>()) {
            context.delete(record)
        }
        for record in try context.fetch(FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>()) {
            context.delete(record)
        }
        for value in sorted {
            context.insert(QuestionBankAnswerStateRecord(
                compoundID: value.compoundID,
                paperID: value.paperID,
                questionID: value.questionID,
                selectedOptionID: value.selectedOptionID,
                isRevealed: value.isRevealed,
                isCleared: value.isCleared,
                mutationRevision: value.mutationRevision,
                updatedAt: value.updatedAt
            ))
        }
        context.insert(QuestionBankAnswerStateMigrationRecord(
            migrationID: clearAllMigrationID,
            sourceKind: "backupRestore",
            sourceBackupPayload: Data(),
            sourceDigest: digest(Data()),
            phaseRawValue: "complete"
        ))
    }

    static func setAllSelectedAnswersRevealed(in container: ModelContainer) async throws {
        let requestedAt = Date.now
        try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
            try await Task.detached(priority: .utility) {
                let context = ModelContext(container)
                while true {
                    let descriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                        predicate: #Predicate {
                            $0.selectedOptionID != nil && !$0.isRevealed && !$0.isCleared
                        },
                        sortBy: [SortDescriptor(\.compoundID)],
                        fetchLimit: batchSize
                    )
                    let page = try context.fetch(descriptor)
                    guard !page.isEmpty else { break }
                    let ids = page.map(\.compoundID)
                    let barrierID = clearAllMigrationID
                    var wasSuppressedByBarrier = false
                    try context.transaction {
                        let barrierDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                            predicate: #Predicate { $0.migrationID == barrierID }
                        )
                        if let barrier = try context.fetch(barrierDescriptor).first,
                           (barrier.sourceKind == "backupRestore" || barrier.sourceKind == "clearAll"),
                           barrier.updatedAt > requestedAt {
                            wasSuppressedByBarrier = true
                            return
                        }
                        for record in page {
                            record.isRevealed = true
                            record.mutationRevision += 1
                            record.updatedAt = .now
                        }
                    }
                    if wasSuppressedByBarrier { break }
                    postChange(ids: ids)
                }
            }.value
        }
    }

    static func postChange(ids: [String], reset: Bool = false, cleared: Bool = false) {
        var userInfo: [AnyHashable: Any] = [resetKey: reset, clearedKey: cleared]
        if !ids.isEmpty { userInfo[changedIDsKey] = ids }
        NotificationCenter.default.post(name: changeNotification, object: nil, userInfo: userInfo)
    }

    static func paperClearMarkerID(_ paperID: String) -> String { "paper::\(paperID)" }

    private static func validatedBackupValues(_ values: [QuestionBankAnswerStateBackup]) throws -> [QuestionBankAnswerStateBackup] {
        var seen = Set<String>()
        for value in values {
            guard value.compoundID == "\(value.paperID)::\(QuestionBankRepository.questionKind)::\(value.questionID)" else {
                throw LegacyBackupImportError.invalidQuestionBankAnswerState(0)
            }
            guard value.mutationRevision >= 0,
                  !value.isCleared || (value.selectedOptionID == nil && !value.isRevealed) else {
                throw LegacyBackupImportError.invalidQuestionBankAnswerState(0)
            }
            guard seen.insert(value.compoundID).inserted else {
                throw LegacyBackupImportError.duplicateQuestionBankAnswerState(value.compoundID)
            }
        }
        return values.sorted { $0.compoundID < $1.compoundID }
    }

    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class QuestionBankAnswerStateStore: ObservableObject {
    static let shared = QuestionBankAnswerStateStore()

    @Published private(set) var cache: [String: QuestionBankAnswerStateValue] = [:]
    @Published private(set) var loadedIDs: Set<String> = []
    @Published private(set) var migrationError: String?
    private var accessOrder: [String: UInt64] = [:]
    private var generationByID: [String: UInt64] = [:]
    private var pendingWritesByID: [String: Task<Void, Error>] = [:]
    private var writeTokenByID: [String: UUID] = [:]
    private var knownContainer: ModelContainer?
    private var cacheEpoch: UInt64 = 0
    private var nextAccess: UInt64 = 0
    private let cacheLimit = 768
    private var notificationObserver: NSObjectProtocol?
    private var isBulkMutationActive = false
    private var clearingIDs = Set<String>()
    private var bulkMutationWaiters: [CheckedContinuation<Void, Never>] = []

    private init() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: QuestionBankAnswerStateRepository.changeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if notification.userInfo?[QuestionBankAnswerStateRepository.resetKey] as? Bool == true {
                    self.cacheEpoch &+= 1
                    self.migrationError = nil
                    self.cache.removeAll()
                    self.loadedIDs.removeAll()
                    self.accessOrder.removeAll()
                    self.pendingWritesByID.removeAll()
                    self.writeTokenByID.removeAll()
                    return
                }
                let ids = notification.userInfo?[QuestionBankAnswerStateRepository.changedIDsKey] as? [String] ?? []
                guard let container = self.knownContainer else { return }
                let hotIDs = ids.filter { self.loadedIDs.contains($0) || self.cache[$0] != nil }
                let refreshableIDs = hotIDs.filter { self.pendingWritesByID[$0] == nil }
                let generations = Dictionary(uniqueKeysWithValues: refreshableIDs.map { id -> (String, UInt64) in
                    self.generationByID[id, default: 0] += 1
                    return (id, self.generationByID[id, default: 0])
                })
                guard !hotIDs.isEmpty else { return }
                if notification.userInfo?[QuestionBankAnswerStateRepository.clearedKey] as? Bool == true {
                    for id in hotIDs {
                        guard let empty = QuestionBankAnswerStateValue.empty(compoundID: id) else { continue }
                        self.cache[id] = QuestionBankAnswerStateValue(
                            compoundID: empty.compoundID,
                            paperID: empty.paperID,
                            questionID: empty.questionID,
                            selectedOptionID: nil,
                            isRevealed: false,
                            isCleared: true,
                            mutationRevision: (self.cache[id]?.mutationRevision ?? 0) + 1,
                            updatedAt: .now
                        )
                        self.loadedIDs.insert(id)
                        self.touch(id)
                    }
                    return
                }
                guard !refreshableIDs.isEmpty else { return }
                do {
                    let values = try await QuestionBankAnswerStateRepository.read(
                        compoundIDs: refreshableIDs,
                        from: container
                    )
                    for id in refreshableIDs where self.generationByID[id, default: 0] == generations[id, default: 0] {
                        if let value = values[id] { self.cache[id] = value }
                        else { self.cache.removeValue(forKey: id) }
                        self.loadedIDs.insert(id)
                        self.touch(id)
                    }
                    self.trimCache(protecting: Set(refreshableIDs))
                } catch {
                    for id in refreshableIDs {
                        self.cache.removeValue(forKey: id)
                        self.loadedIDs.remove(id)
                    }
                }
            }
        }
    }

    func value(for compoundID: String) -> QuestionBankAnswerStateValue? {
        touch(compoundID)
        return cache[compoundID]
    }

    func isLoaded(_ compoundID: String) -> Bool { loadedIDs.contains(compoundID) }

    func load(_ compoundIDs: [String], from container: ModelContainer) async throws {
        knownContainer = container
        let requested = Array(Set(compoundIDs)).sorted()
        guard !requested.isEmpty else { return }
        let startingEpoch = cacheEpoch
        let startingGenerations = Dictionary(uniqueKeysWithValues: requested.map { ($0, generationByID[$0, default: 0]) })
        let result = try await QuestionBankAnswerStateRepository.read(compoundIDs: requested, from: container)
        guard cacheEpoch == startingEpoch else { return }
        for id in requested where generationByID[id, default: 0] == startingGenerations[id, default: 0] {
            if let value = result[id] { cache[id] = value }
            else { cache.removeValue(forKey: id) }
            loadedIDs.insert(id)
            touch(id)
        }
        trimCache(protecting: Set(requested))
    }

    func setSelection(
        _ optionID: String?,
        for compoundID: String,
        paperID: String,
        questionID: String,
        revealed: Bool,
        in container: ModelContainer
    ) async throws {
        knownContainer = container
        let old = cache[compoundID]
        let value = QuestionBankAnswerStateValue(
            compoundID: compoundID,
            paperID: paperID,
            questionID: questionID,
            selectedOptionID: optionID,
            isRevealed: revealed,
            isCleared: false,
            mutationRevision: (old?.mutationRevision ?? 0) + 1,
            updatedAt: .now
        )
        try await commit(value, in: container)
    }

    func setRevealed(
        _ revealed: Bool,
        for compoundID: String,
        paperID: String,
        questionID: String,
        in container: ModelContainer
    ) async throws {
        knownContainer = container
        if !isLoaded(compoundID) { try await load([compoundID], from: container) }
        let old = cache[compoundID]
        let value = QuestionBankAnswerStateValue(
            compoundID: compoundID,
            paperID: paperID,
            questionID: questionID,
            selectedOptionID: old?.selectedOptionID,
            isRevealed: revealed,
            isCleared: false,
            mutationRevision: (old?.mutationRevision ?? 0) + 1,
            updatedAt: .now
        )
        try await commit(value, in: container)
    }

    func clear(_ compoundIDs: [String], paperScope: String? = nil, in container: ModelContainer) async throws {
        knownContainer = container
        let ids = Array(Set(compoundIDs))
        guard !isBulkMutationActive,
              bulkMutationWaiters.isEmpty,
              clearingIDs.isDisjoint(with: ids) else {
            throw QuestionBankAnswerStateRepositoryError.mutationInProgress
        }
        clearingIDs.formUnion(ids)
        defer { finishClearing(ids) }
        let hotIDs = Set(ids.filter { loadedIDs.contains($0) || cache[$0] != nil })
        for id in ids {
            if let pendingWrite = pendingWritesByID[id] { _ = try? await pendingWrite.value }
        }
        try await QuestionBankAnswerStateRepository.clear(compoundIDs: ids, paperScope: paperScope, in: container)
        for id in hotIDs {
            generationByID[id, default: 0] += 1
            if let empty = QuestionBankAnswerStateValue.empty(compoundID: id) {
                cache[id] = QuestionBankAnswerStateValue(
                    compoundID: empty.compoundID,
                    paperID: empty.paperID,
                    questionID: empty.questionID,
                    selectedOptionID: nil,
                    isRevealed: false,
                    isCleared: true,
                    mutationRevision: (cache[id]?.mutationRevision ?? 0) + 1,
                    updatedAt: .now
                )
            }
            loadedIDs.insert(id)
            touch(id)
        }
        trimCache(protecting: hotIDs)
    }

    func markAllSelectedRevealed(in container: ModelContainer) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        try await QuestionBankAnswerStateRepository.setAllSelectedAnswersRevealed(in: container)
    }

    func replaceFromBackup(_ values: [QuestionBankAnswerStateBackup], in container: ModelContainer) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        try await QuestionBankAnswerStateRepository.replaceFromBackup(values, in: container)
        clearCachedValues()
    }

    func readAllForBackup(in container: ModelContainer) async throws -> [QuestionBankAnswerStateBackup] {
        knownContainer = container
        await waitForPendingWrites()
        return try await QuestionBankAnswerStateRepository.readAllForBackup(from: container)
    }

    func clearAllLocalData(in container: ModelContainer) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        try await QuestionBankAnswerStateRepository.clearAllLocalData(in: container)
        clearCachedValues()
    }

    func restoreLocalData(with package: LegacyImportPackage, in container: ModelContainer) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        try await LegacyBackupRestorer.replace(with: package, in: container)
        clearCachedValues()
    }

    func migrateGlobalIfNeeded(in container: ModelContainer) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        let sourceKey = QuestionBankAnswerStateStorage.appStorageKey
        let rawValue = await Task.detached(priority: .utility) {
            UserDefaults.standard.string(forKey: sourceKey) ?? QuestionBankAnswerStateStorage.emptyValue
        }.value
        let rawPayload = Data(rawValue.utf8)
        do {
            try await QuestionBankAnswerStateMigrationService.shared.migrate(
                migrationID: "legacy-global-v1-\(QuestionBankAnswerStateRepository.digest(rawPayload))",
                sourceKind: "global-v1",
                sourceBackupPayload: rawPayload,
                paperID: nil,
                container: container
            )
            migrationError = nil
        } catch {
            migrationError = error.localizedDescription
            throw error
        }
        await Task.detached(priority: .utility) {
            if UserDefaults.standard.string(forKey: sourceKey) == rawValue {
                UserDefaults.standard.removeObject(forKey: sourceKey)
            }
        }.value
        clearCachedValues()
    }

    func migrateSceneStorageIfNeeded(
        sourceKey: String,
        selectedOptionsJSON: String,
        revealedAnswersJSON: String,
        paperID: String?,
        in container: ModelContainer
    ) async throws {
        await beginBulkMutation()
        defer { finishBulkMutation() }
        knownContainer = container
        await waitForPendingWrites()
        let source = QuestionBankAnswerLegacySceneSource(
            sourceKey: sourceKey,
            selectedOptionsJSON: selectedOptionsJSON,
            revealedAnswersJSON: revealedAnswersJSON,
            paperID: paperID
        )
        let raw = try JSONEncoder().encode(source)
        do {
            try await QuestionBankAnswerStateMigrationService.shared.migrate(
                migrationID: "legacy-scene-v1-\(QuestionBankAnswerStateRepository.digest(raw))",
                sourceKind: "scene-storage-v1",
                sourceBackupPayload: raw,
                paperID: paperID,
                container: container
            )
            migrationError = nil
            clearCachedValues()
        } catch {
            migrationError = error.localizedDescription
            throw error
        }
    }

    private func commit(_ value: QuestionBankAnswerStateValue, in container: ModelContainer) async throws {
        guard !isBulkMutationActive,
              bulkMutationWaiters.isEmpty,
              !clearingIDs.contains(value.compoundID) else {
            throw QuestionBankAnswerStateRepositoryError.mutationInProgress
        }
        knownContainer = container
        let id = value.compoundID
        let token = UUID()
        let epoch = cacheEpoch
        let previousWrite = pendingWritesByID[id]
        writeTokenByID[id] = token
        generationByID[id, default: 0] += 1
        cache[id] = value
        loadedIDs.insert(id)
        touch(id)
        trimCache(protecting: [id])
        let write = Task { @MainActor [weak self] in
            if let previousWrite { _ = try? await previousWrite.value }
            try await QuestionBankAnswerStateRepository.upsert(value, in: container)
            let persisted = try await QuestionBankAnswerStateRepository.read(compoundIDs: [id], from: container)
            guard let self, self.cacheEpoch == epoch, self.writeTokenByID[id] == token else { return }
            self.cache[id] = persisted[id]
            self.loadedIDs.insert(id)
            self.touch(id)
            self.pendingWritesByID.removeValue(forKey: id)
            self.writeTokenByID.removeValue(forKey: id)
        }
        pendingWritesByID[id] = write
        do {
            try await write.value
        } catch {
            if writeTokenByID[id] == token {
                writeTokenByID.removeValue(forKey: id)
                pendingWritesByID.removeValue(forKey: id)
                generationByID[id, default: 0] += 1
                cache.removeValue(forKey: id)
                loadedIDs.remove(id)
            }
            throw error
        }
    }

    private func touch(_ id: String) {
        nextAccess &+= 1
        accessOrder[id] = nextAccess
    }

    private func beginBulkMutation() async {
        if !isBulkMutationActive, clearingIDs.isEmpty, bulkMutationWaiters.isEmpty {
            isBulkMutationActive = true
            return
        }
        await withCheckedContinuation { continuation in
            bulkMutationWaiters.append(continuation)
        }
    }

    private func finishBulkMutation() {
        if bulkMutationWaiters.isEmpty {
            isBulkMutationActive = false
        } else {
            bulkMutationWaiters.removeFirst().resume()
        }
    }

    private func finishClearing(_ ids: [String]) {
        clearingIDs.subtract(ids)
        guard !isBulkMutationActive, clearingIDs.isEmpty, !bulkMutationWaiters.isEmpty else { return }
        isBulkMutationActive = true
        bulkMutationWaiters.removeFirst().resume()
    }

    private func waitForPendingWrites() async {
        for pendingWrite in Array(pendingWritesByID.values) {
            _ = try? await pendingWrite.value
        }
    }

    private func clearCachedValues() {
        cacheEpoch &+= 1
        cache.removeAll()
        loadedIDs.removeAll()
        accessOrder.removeAll()
        pendingWritesByID.removeAll()
        writeTokenByID.removeAll()
    }

    private func trimCache(protecting protectedIDs: Set<String>) {
        guard cache.count > cacheLimit else { return }
        let removable = cache.keys
            .filter { !protectedIDs.contains($0) }
            .sorted { accessOrder[$0, default: 0] < accessOrder[$1, default: 0] }
        for id in removable.prefix(cache.count - cacheLimit) {
            cache.removeValue(forKey: id)
            loadedIDs.remove(id)
            accessOrder.removeValue(forKey: id)
        }
    }
}

private struct QuestionBankAnswerLegacySceneSource: Codable, Sendable {
    let sourceKey: String
    let selectedOptionsJSON: String
    let revealedAnswersJSON: String
    let paperID: String?
}

private struct QuestionBankAnswerLegacyItem: Sendable {
    let value: QuestionBankAnswerStateValue
}

@MainActor
private final class QuestionBankAnswerStateMigrationService {
    static let shared = QuestionBankAnswerStateMigrationService()
    private var activeTasks: [String: Task<Void, Error>] = [:]

    func migrate(
        migrationID: String,
        sourceKind: String,
        sourceBackupPayload: Data,
        paperID: String?,
        container: ModelContainer
    ) async throws {
        if let active = activeTasks[migrationID] {
            try await active.value
            return
        }
        let task = Task.detached(priority: .utility) {
            try await QuestionBankAnswerStateMutationCoordinator.shared.withExclusive {
                try await Self.run(
                    migrationID: migrationID,
                    sourceKind: sourceKind,
                    sourceBackupPayload: sourceBackupPayload,
                    paperID: paperID,
                    container: container
                )
            }
        }
        activeTasks[migrationID] = task
        defer { activeTasks.removeValue(forKey: migrationID) }
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            Task { await self.cancelMigration(migrationID) }
        }
    }

    private func cancelMigration(_ migrationID: String) {
        activeTasks[migrationID]?.cancel()
    }

    nonisolated private static func run(
        migrationID: String,
        sourceKind: String,
        sourceBackupPayload: Data,
        paperID: String?,
        container: ModelContainer
    ) async throws {
        let digest = QuestionBankAnswerStateRepository.digest(sourceBackupPayload)
        let context = ModelContext(container)
        guard try persistBackupIfNeeded(
            migrationID: migrationID,
            sourceKind: sourceKind,
            payload: sourceBackupPayload,
            digest: digest,
            context: context
        ) else { return }

        do {
            if try isClearedAllBarrierPresent(context: context) {
                try markMigrationComplete(migrationID: migrationID, context: context)
                return
            }
            let progress = try fetchMigration(migrationID, context: context)
            guard let progress else { throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("备份记录丢失") }
            if progress.phaseRawValue == "complete" { return }
            guard progress.formatVersion == 1 else {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("不支持的迁移备份版本 \(progress.formatVersion)")
            }
            guard QuestionBankAnswerStateRepository.digest(progress.sourceBackupPayload) == progress.sourceDigest else {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("原始作答备份校验失败")
            }

            var items = try await decodeLegacyItems(
                kind: progress.sourceKind,
                payload: progress.sourceBackupPayload,
                paperIDHint: paperID,
                container: container
            )
            items.sort { $0.value.compoundID < $1.value.compoundID }
            try updateSourceCount(items.count, migrationID: migrationID, context: context)

            guard let persistedProgress = try fetchMigration(migrationID, context: context) else {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("迁移进度记录丢失")
            }
            var cursor = persistedProgress.cursor
            guard cursor >= 0, cursor <= items.count,
                  persistedProgress.processedItemCount == cursor,
                  persistedProgress.sourceItemCount == items.count else {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("迁移进度与原始备份不一致")
            }
            while cursor < items.count {
                try Task.checkCancellation()
                let end = min(cursor + QuestionBankAnswerStateRepository.batchSize, items.count)
                let page = Array(items[cursor..<end])
                let clearAllID = QuestionBankAnswerStateRepository.clearAllMigrationID
                var wasSuppressedByBarrier = false
                try context.transaction {
                    let barrierDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                        predicate: #Predicate { $0.migrationID == clearAllID }
                    )
                    if try !context.fetch(barrierDescriptor).isEmpty {
                        wasSuppressedByBarrier = true
                        let migrationDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                            predicate: #Predicate { $0.migrationID == migrationID }
                        )
                        if let migration = try context.fetch(migrationDescriptor).first {
                            migration.phaseRawValue = "complete"
                            migration.cursor = migration.sourceItemCount
                            migration.processedItemCount = migration.sourceItemCount
                            migration.lastError = nil
                            migration.updatedAt = .now
                        }
                        return
                    }

                    let pageIDs = page.map { $0.value.compoundID }
                    let existingDescriptor = FetchDescriptor<QuestionBankAnswerStateRecord>(
                        predicate: #Predicate { pageIDs.contains($0.compoundID) }
                    )
                    let existing = try context.fetch(existingDescriptor)
                    let existingIDs = Set(existing.map(\.compoundID))
                    let clearMarkerIDs = page.map { QuestionBankAnswerStateRepository.paperClearMarkerID($0.value.paperID) }
                    let clearMarkerDescriptor = FetchDescriptor<QuestionBankAnswerStateScopeClearRecord>(
                        predicate: #Predicate { clearMarkerIDs.contains($0.scopeID) }
                    )
                    let clearedPapers = Set(try context.fetch(clearMarkerDescriptor).compactMap(\.paperID))

                    for item in page where !existingIDs.contains(item.value.compoundID)
                        && !clearedPapers.contains(item.value.paperID) {
                        let value = item.value
                        context.insert(QuestionBankAnswerStateRecord(
                            compoundID: value.compoundID,
                            paperID: value.paperID,
                            questionID: value.questionID,
                            selectedOptionID: value.selectedOptionID,
                            isRevealed: value.isRevealed,
                            isCleared: value.isCleared,
                            mutationRevision: 1,
                            updatedAt: .now
                        ))
                    }

                    let migrationDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                        predicate: #Predicate { $0.migrationID == migrationID }
                    )
                    if let migration = try context.fetch(migrationDescriptor).first {
                        migration.cursor = end
                        migration.processedItemCount = end
                        migration.phaseRawValue = end == items.count ? "complete" : "migrating"
                        migration.lastError = nil
                        migration.updatedAt = .now
                    }
                }
                if wasSuppressedByBarrier { return }
                cursor = end
                QuestionBankAnswerStateRepository.postChange(ids: page.map { $0.value.compoundID })
            }
            if items.isEmpty { try markMigrationComplete(migrationID: migrationID, context: context) }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try markMigrationFailed(migrationID: migrationID, message: error.localizedDescription, context: context)
            throw error
        }
    }

    nonisolated private static func decodeLegacyItems(
        kind: String,
        payload: Data,
        paperIDHint: String?,
        container: ModelContainer
    ) async throws -> [QuestionBankAnswerLegacyItem] {
        var selected: [String: String] = [:]
        var revealed = Set<String>()
        var resolved = Set<String>()
        var resolvedPaperIDHint = paperIDHint

        switch kind {
        case "global-v1":
            let raw = String(data: payload, encoding: .utf8) ?? ""
            if raw != QuestionBankAnswerStateStorage.emptyValue, !raw.isEmpty {
                do {
                    let state = try JSONDecoder().decode(QuestionBankAnswerState.self, from: payload)
                    selected = state.selectedOptions
                    revealed = state.revealedQuestionIDs
                    resolved = state.legacyResolvedQuestionIDs
                } catch {
                    throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload(error.localizedDescription)
                }
            }
        case "scene-storage-v1":
            do {
                let source = try JSONDecoder().decode(QuestionBankAnswerLegacySceneSource.self, from: payload)
                selected = try decodeRequiredJSON([String: String].self, from: source.selectedOptionsJSON)
                revealed = Set(try decodeRequiredJSON([String].self, from: source.revealedAnswersJSON))
                resolvedPaperIDHint = source.paperID
            } catch {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload(error.localizedDescription)
            }
        default:
            throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("不支持的数据来源 \(kind)")
        }

        let sourceIDs = Set(selected.keys).union(revealed).union(resolved).sorted()
        guard !sourceIDs.isEmpty else { return [] }
        var directory: QuestionBankReaderDirectorySnapshot?
        if resolvedPaperIDHint == nil, sourceIDs.contains(where: { QuestionBankAnswerStateValue.empty(compoundID: $0) == nil }) {
            directory = try await QuestionBankCatalogService.readerDirectory(in: container)
        }

        return try sourceIDs.map { sourceID in
            let compoundID: String
            if QuestionBankAnswerStateValue.empty(compoundID: sourceID) != nil {
                compoundID = sourceID
            } else if let resolvedPaperIDHint {
                compoundID = "\(resolvedPaperIDHint)::\(QuestionBankRepository.questionKind)::\(sourceID)"
            } else if let matches = directory?.questions.filter({ $0.questionID == sourceID }), matches.count == 1 {
                compoundID = matches[0].sourceCompoundID
            } else {
                throw QuestionBankAnswerStateRepositoryError.ambiguousLegacyQuestionID(sourceID)
            }
            guard var value = QuestionBankAnswerStateValue.empty(compoundID: compoundID) else {
                throw QuestionBankAnswerStateRepositoryError.invalidCompoundID(compoundID)
            }
            value.selectedOptionID = selected[sourceID]
            value.isRevealed = revealed.contains(sourceID)
            value.isCleared = value.selectedOptionID == nil && !value.isRevealed
            return QuestionBankAnswerLegacyItem(value: value)
        }
    }

    nonisolated private static func decodeRequiredJSON<T: Decodable>(_ type: T.Type, from raw: String) throws -> T {
        guard let data = raw.data(using: .utf8) else {
            throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("文字编码无效")
        }
        return try JSONDecoder().decode(type, from: data)
    }

    nonisolated private static func persistBackupIfNeeded(
        migrationID: String,
        sourceKind: String,
        payload: Data,
        digest: String,
        context: ModelContext
    ) throws -> Bool {
        let descriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
            predicate: #Predicate { $0.migrationID == migrationID }
        )
        if let existing = try context.fetch(descriptor).first {
            guard existing.sourceKind == sourceKind,
                  existing.formatVersion == 1,
                  existing.sourceDigest == digest,
                  existing.sourceBackupPayload == payload else {
                throw QuestionBankAnswerStateRepositoryError.invalidLegacyPayload("同一迁移 ID 对应了不同的原始备份")
            }
            return true
        }
        let clearAllID = QuestionBankAnswerStateRepository.clearAllMigrationID
        var suppressedByBarrier = false
        try context.transaction {
            let barrierDescriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
                predicate: #Predicate { $0.migrationID == clearAllID }
            )
            if try !context.fetch(barrierDescriptor).isEmpty {
                suppressedByBarrier = true
                return
            }
            if try context.fetch(descriptor).first != nil { return }
            context.insert(QuestionBankAnswerStateMigrationRecord(
                migrationID: migrationID,
                sourceKind: sourceKind,
                sourceBackupPayload: payload,
                sourceDigest: digest
            ))
        }
        return !suppressedByBarrier
    }

    nonisolated private static func fetchMigration(
        _ migrationID: String,
        context: ModelContext
    ) throws -> QuestionBankAnswerStateMigrationRecord? {
        let descriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
            predicate: #Predicate { $0.migrationID == migrationID }
        )
        return try context.fetch(descriptor).first
    }

    nonisolated private static func isClearedAllBarrierPresent(context: ModelContext) throws -> Bool {
        let clearAllID = QuestionBankAnswerStateRepository.clearAllMigrationID
        let descriptor = FetchDescriptor<QuestionBankAnswerStateMigrationRecord>(
            predicate: #Predicate { $0.migrationID == clearAllID }
        )
        return try !context.fetch(descriptor).isEmpty
    }

    nonisolated private static func updateSourceCount(
        _ count: Int,
        migrationID: String,
        context: ModelContext
    ) throws {
        try context.transaction {
            guard let migration = try fetchMigration(migrationID, context: context) else { return }
            migration.sourceItemCount = count
            migration.phaseRawValue = "migrating"
            migration.lastError = nil
            migration.updatedAt = .now
        }
    }

    nonisolated private static func markMigrationComplete(migrationID: String, context: ModelContext) throws {
        try context.transaction {
            guard let migration = try fetchMigration(migrationID, context: context) else { return }
            migration.phaseRawValue = "complete"
            migration.cursor = migration.sourceItemCount
            migration.processedItemCount = migration.sourceItemCount
            migration.lastError = nil
            migration.updatedAt = .now
        }
    }

    nonisolated private static func markMigrationFailed(
        migrationID: String,
        message: String,
        context: ModelContext
    ) throws {
        try context.transaction {
            guard let migration = try fetchMigration(migrationID, context: context) else { return }
            migration.phaseRawValue = "failed"
            migration.lastError = message
            migration.updatedAt = .now
        }
    }
}
