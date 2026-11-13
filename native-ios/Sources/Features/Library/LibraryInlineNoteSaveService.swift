import Combine
import CryptoKit
import Foundation
import UIKit

struct LibraryInlineNoteDraftSnapshot: Codable, Equatable, Sendable {
    let recordID: String
    let baseVersion: String
    let draftVersion: UInt64
    let content: String
    let updatedAt: Date
}

struct LibraryInlineNotePreparedSave: Sendable {
    let content: String
    let payload: Data
    let indexPayload: Data?
    let updatedAt: Date
    let version: String
}

enum LibraryInlineNoteSavePhase: String, Equatable, Sendable {
    case idle
    case debouncing
    case queued
    case writing
    case saved
    case failed
}

struct LibraryInlineNoteRecordSaveState: Equatable, Sendable {
    var latestDraftVersion: UInt64 = 0
    var latestContent = ""
    var latestBaseVersion: String?
    var latestBasePayload: Data?
    var confirmedDraftVersion: UInt64 = 0
    var confirmedContent = ""
    var confirmedRecordVersion: String?
    var phase: LibraryInlineNoteSavePhase = .idle
    var errorMessage: String?
}

/// All note draft file operations pass through one actor, so a commit cleanup
/// cannot race a newer atomic snapshot write for the same record.
actor LibraryInlineNoteDraftStorage {
    static let shared = LibraryInlineNoteDraftStorage()

    private func url(recordID: String) throws -> URL {
        guard let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw CocoaError(.fileNoSuchFile)
        }
        let directory = root.appendingPathComponent("LibraryInlineNoteDrafts", isDirectory: true)
        let fileKey = Data(recordID.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return directory.appendingPathComponent(fileKey).appendingPathExtension("json")
    }

    func load(recordID: String) throws -> LibraryInlineNoteDraftSnapshot? {
        let fileURL = try url(recordID: recordID)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        let snapshot = try JSONDecoder().decode(LibraryInlineNoteDraftSnapshot.self, from: data)
        guard snapshot.recordID == recordID else { return nil }
        return snapshot
    }

    func write(_ snapshot: LibraryInlineNoteDraftSnapshot) throws {
        let fileURL = try url(recordID: snapshot.recordID)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONEncoder().encode(snapshot)
        try data.write(to: fileURL, options: .atomic)
    }

    func removeIfMatching(recordID: String, draftVersion: UInt64) throws {
        guard let current = try load(recordID: recordID), current.draftVersion == draftVersion else { return }
        try FileManager.default.removeItem(at: url(recordID: recordID))
    }
}

@MainActor
final class LibraryInlineNoteSaveService: ObservableObject {
    static let shared = LibraryInlineNoteSaveService()

    typealias Commit = @MainActor (LibraryInlineNotePreparedSave?, String) throws -> String
    typealias Completion = @MainActor (Result<String, Error>) -> Void

    private struct RecordVersion: Hashable {
        let recordID: String
        let draftVersion: UInt64
    }

    private struct Job {
        let snapshot: LibraryInlineNoteDraftSnapshot
        let basePayload: Data?
        let collection: String
        let commit: Commit
    }

    private struct VersionChain {
        var knownVersions: Set<String>
        var latestVersion: String
        var latestPayload: Data?
    }

    @Published private(set) var recordStates: [String: LibraryInlineNoteRecordSaveState] = [:]

    private var queues: [String: [Job]] = [:]
    private var workers: [String: Task<Void, Never>] = [:]
    private var enqueuedVersions: Set<RecordVersion> = []
    private var completions: [RecordVersion: [Completion]] = [:]
    private var idleHandlers: [String: [@MainActor (Bool) -> Void]] = [:]
    private var committedVersionChains: [String: VersionChain] = [:]
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func state(recordID: String) -> LibraryInlineNoteRecordSaveState {
        recordStates[recordID] ?? LibraryInlineNoteRecordSaveState()
    }

    func hasPending(recordID: String) -> Bool {
        workers[recordID] != nil || !(queues[recordID]?.isEmpty ?? true)
    }

    func markExistingContentConfirmed(
        recordID: String,
        content: String,
        recordVersion: String,
        payload: Data?
    ) {
        guard !hasPending(recordID: recordID) else { return }
        var state = self.state(recordID: recordID)
        guard state.phase == .idle
                || state.phase == .saved
                || (state.phase == .failed && state.latestContent == content) else { return }
        state.latestContent = content
        state.latestBaseVersion = recordVersion
        state.latestBasePayload = payload
        state.confirmedContent = content
        state.confirmedRecordVersion = recordVersion
        state.confirmedDraftVersion = state.latestDraftVersion
        state.phase = .saved
        state.errorMessage = nil
        recordStates[recordID] = state
    }

    /// Registers each distinct editor revision before its debounce begins.
    /// A completed callback for an older revision therefore cannot mark newer
    /// text as saved or failed.
    func registerDraft(
        recordID: String,
        content: String,
        baseVersion: String,
        basePayload: Data?
    ) -> UInt64 {
        var state = self.state(recordID: recordID)
        if state.latestContent == content,
           state.latestDraftVersion > 0 || state.latestContent == state.confirmedContent {
            return state.latestDraftVersion
        }

        let nextVersion = max(state.latestDraftVersion, state.confirmedDraftVersion) &+ 1
        state.latestDraftVersion = nextVersion
        state.latestContent = content
        state.latestBaseVersion = baseVersion
        state.latestBasePayload = basePayload
        state.errorMessage = nil
        if content == state.confirmedContent, !hasPending(recordID: recordID) {
            state.confirmedDraftVersion = nextVersion
            state.phase = .saved
        } else {
            state.phase = .debouncing
        }
        recordStates[recordID] = state
        return nextVersion
    }

    /// Restores a durable revision without inventing a new draft version.
    func restoreDraft(
        recordID: String,
        content: String,
        draftVersion: UInt64,
        baseVersion: String,
        basePayload: Data?
    ) -> Bool {
        var state = self.state(recordID: recordID)
        guard draftVersion >= state.latestDraftVersion || state.latestContent == content else { return false }
        if draftVersion == state.latestDraftVersion,
           state.latestDraftVersion > 0,
           state.latestContent != content {
            return false
        }
        let preserveFailure = state.phase == .failed
            && state.latestDraftVersion >= draftVersion
            && state.latestContent == content
        state.latestDraftVersion = max(draftVersion, state.latestDraftVersion)
        state.latestContent = content
        state.latestBaseVersion = baseVersion
        state.latestBasePayload = basePayload
        state.phase = preserveFailure ? .failed : .queued
        if !preserveFailure { state.errorMessage = nil }
        recordStates[recordID] = state
        return true
    }

    func markDebouncing(recordID: String, draftVersion: UInt64) {
        updateState(recordID: recordID) { state in
            guard state.latestDraftVersion == draftVersion,
                  state.phase != .queued, state.phase != .writing else { return }
            state.phase = .debouncing
            state.errorMessage = nil
        }
    }

    func enqueue(
        recordID: String,
        draftVersion: UInt64,
        baseVersion: String,
        basePayload: Data?,
        collection: String = "",
        content: String,
        updatedAt: Date = .now,
        requiresBackgroundTime: Bool = false,
        commit: @escaping Commit,
        completion: @escaping Completion = { _ in }
    ) {
        let key = RecordVersion(recordID: recordID, draftVersion: draftVersion)
        var state = self.state(recordID: recordID)
        guard state.latestDraftVersion == draftVersion, state.latestContent == content else {
            completion(.failure(LibraryInlineNoteSaveError.staleDraft))
            return
        }

        if state.confirmedDraftVersion == draftVersion, state.confirmedContent == content {
            completion(.success(state.confirmedRecordVersion ?? baseVersion))
            return
        }

        completions[key, default: []].append(completion)
        guard enqueuedVersions.insert(key).inserted else { return }

        let snapshot = LibraryInlineNoteDraftSnapshot(
            recordID: recordID,
            baseVersion: baseVersion,
            draftVersion: draftVersion,
            content: content,
            updatedAt: updatedAt
        )
        queues[recordID, default: []].append(
            Job(
                snapshot: snapshot,
                basePayload: basePayload,
                collection: collection,
                commit: commit
            )
        )
        if state.latestDraftVersion == draftVersion {
            state.latestBaseVersion = baseVersion
            state.latestBasePayload = basePayload
            state.phase = .queued
            state.errorMessage = nil
            recordStates[recordID] = state
        }
        if requiresBackgroundTime { beginBackgroundExecutionIfNeeded() }
        if workers[recordID] == nil {
            workers[recordID] = Task { await drain(recordID: recordID) }
        }
    }

    func whenIdle(recordID: String, perform action: @escaping @MainActor (Bool) -> Void) {
        guard hasPending(recordID: recordID) else {
            let state = self.state(recordID: recordID)
            action(state.phase != .failed && state.latestContent == state.confirmedContent)
            return
        }
        idleHandlers[recordID, default: []].append(action)
    }

    private func drain(recordID: String) async {
        while var queue = queues[recordID], !queue.isEmpty {
            let job = queue.removeFirst()
            queues[recordID] = queue
            let key = RecordVersion(recordID: recordID, draftVersion: job.snapshot.draftVersion)
            updateState(recordID: recordID) { state in
                if state.latestDraftVersion == job.snapshot.draftVersion {
                    state.phase = .writing
                    state.errorMessage = nil
                }
            }

            do {
                try await LibraryInlineNoteDraftStorage.shared.write(job.snapshot)
                await Task.yield()

                let chain = committedVersionChains[recordID]
                let preparationBase = if let chain,
                    chain.knownVersions.contains(job.snapshot.baseVersion) {
                    chain.latestPayload ?? job.basePayload
                } else {
                    job.basePayload
                }
                let prepared: LibraryInlineNotePreparedSave?
                if let preparationBase {
                    prepared = try await Self.prepare(
                        basePayload: preparationBase,
                        collection: job.collection,
                        content: job.snapshot.content,
                        updatedAt: job.snapshot.updatedAt
                    )
                } else {
                    prepared = nil
                }

                let expectedVersion: String
                if let chain, chain.knownVersions.contains(job.snapshot.baseVersion) {
                    expectedVersion = chain.latestVersion
                } else {
                    expectedVersion = job.snapshot.baseVersion
                }
                let committedVersion = try job.commit(prepared, expectedVersion)

                var updatedChain = committedVersionChains[recordID] ?? VersionChain(
                    knownVersions: [],
                    latestVersion: job.snapshot.baseVersion,
                    latestPayload: job.basePayload
                )
                updatedChain.knownVersions.insert(job.snapshot.baseVersion)
                updatedChain.knownVersions.insert(expectedVersion)
                updatedChain.knownVersions.insert(committedVersion)
                updatedChain.latestVersion = committedVersion
                updatedChain.latestPayload = prepared?.payload ?? updatedChain.latestPayload
                committedVersionChains[recordID] = updatedChain

                do {
                    try await LibraryInlineNoteDraftStorage.shared.removeIfMatching(
                        recordID: recordID,
                        draftVersion: job.snapshot.draftVersion
                    )
                } catch {
                    LibraryPerformanceLog.event(
                        "note.draft.cleanup.failed id=\(LibraryPerformanceLog.shortIdentifier(recordID)) revision=\(job.snapshot.draftVersion) error=\(error.localizedDescription)"
                    )
                }

                updateState(recordID: recordID) { state in
                    state.confirmedDraftVersion = max(state.confirmedDraftVersion, job.snapshot.draftVersion)
                    state.confirmedContent = job.snapshot.content
                    state.confirmedRecordVersion = committedVersion
                    if state.latestDraftVersion == job.snapshot.draftVersion {
                        state.latestBaseVersion = committedVersion
                        state.latestBasePayload = prepared?.payload ?? job.basePayload
                        state.phase = .saved
                        state.errorMessage = nil
                    } else {
                        let latestBaseBelongsToThisChain = state.latestBaseVersion == job.snapshot.baseVersion
                            || state.latestBaseVersion == expectedVersion
                            || (state.latestBaseVersion.map { chain?.knownVersions.contains($0) == true } ?? false)
                        if latestBaseBelongsToThisChain {
                            state.latestBaseVersion = committedVersion
                            state.latestBasePayload = prepared?.payload ?? job.basePayload
                        }
                        if self.hasQueuedDraft(recordID: recordID, draftVersion: state.latestDraftVersion) {
                            state.phase = .queued
                        }
                    }
                }
                resolveCompletions(for: key, result: .success(committedVersion))
            } catch {
                updateState(recordID: recordID) { state in
                    if state.latestDraftVersion == job.snapshot.draftVersion {
                        state.phase = .failed
                        state.errorMessage = error.localizedDescription
                    } else if !self.hasQueuedDraft(recordID: recordID, draftVersion: state.latestDraftVersion),
                              state.phase != .debouncing {
                        state.phase = .failed
                        state.errorMessage = "较早版本保存失败；最新草稿仍待保存。\(error.localizedDescription)"
                    }
                }
                LibraryPerformanceLog.event(
                    "note.save.failed id=\(LibraryPerformanceLog.shortIdentifier(recordID)) revision=\(job.snapshot.draftVersion) error=\(error.localizedDescription)"
                )
                resolveCompletions(for: key, result: .failure(error))
            }
            enqueuedVersions.remove(key)
        }

        committedVersionChains[recordID] = nil
        workers[recordID] = nil
        queues[recordID] = nil
        endBackgroundExecutionIfIdle()
        let handlers = idleHandlers.removeValue(forKey: recordID) ?? []
        let state = self.state(recordID: recordID)
        let succeeded = state.phase != .failed && state.latestContent == state.confirmedContent
        handlers.forEach { $0(succeeded) }
    }

    private func updateState(
        recordID: String,
        _ update: (inout LibraryInlineNoteRecordSaveState) -> Void
    ) {
        var state = self.state(recordID: recordID)
        update(&state)
        recordStates[recordID] = state
    }

    private func hasQueuedDraft(recordID: String, draftVersion: UInt64) -> Bool {
        queues[recordID]?.contains(where: { $0.snapshot.draftVersion == draftVersion }) == true
    }

    private func resolveCompletions(for key: RecordVersion, result: Result<String, Error>) {
        let callbacks = completions.removeValue(forKey: key) ?? []
        callbacks.forEach { $0(result) }
    }

    private func beginBackgroundExecutionIfNeeded() {
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "LibraryInlineNoteSave") { [weak self] in
            Task { @MainActor in self?.backgroundTaskID = .invalid }
        }
    }

    private func endBackgroundExecutionIfIdle() {
        guard workers.isEmpty, backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    private static func prepare(
        basePayload: Data,
        collection: String,
        content: String,
        updatedAt: Date
    ) async throws -> LibraryInlineNotePreparedSave {
        try await Task.detached(priority: .utility) {
            guard var object = (try JSONSerialization.jsonObject(with: basePayload)) as? [String: Any] else {
                throw LibraryInlineNoteSavePreparationError.invalidPayload
            }
            object["note"] = content
            object["updatedAt"] = ISO8601DateFormatter().string(from: updatedAt)
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let indexPayload = StoredRecord.makeIndexPayload(from: payload, collection: collection)
            return LibraryInlineNotePreparedSave(
                content: content,
                payload: payload,
                indexPayload: indexPayload,
                updatedAt: updatedAt,
                version: versionKey(updatedAt: updatedAt, payload: payload)
            )
        }.value
    }

    nonisolated static func versionKey(updatedAt: Date?, payload: Data) -> String {
        let payloadDigest = SHA256.hash(data: payload).map { String(format: "%02x", Int($0)) }.joined()
        let dateKey = updatedAt.map { String($0.timeIntervalSince1970.bitPattern, radix: 16) } ?? "none"
        return "\(dateKey):\(payloadDigest)"
    }
}

private enum LibraryInlineNoteSaveError: LocalizedError {
    case staleDraft

    var errorDescription: String? {
        switch self {
        case .staleDraft: "笔记草稿已更新，旧版本没有覆盖新内容。"
        }
    }
}

private enum LibraryInlineNoteSavePreparationError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "原题目数据无法解析，笔记未写入，也没有覆盖原记录。"
        }
    }
}
