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

enum LibraryInlineNoteDraftStorage {
    private static func url(recordID: String) throws -> URL {
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

    static func load(recordID: String) async throws -> LibraryInlineNoteDraftSnapshot? {
        try await Task.detached(priority: .utility) {
            let fileURL = try url(recordID: recordID)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
            let data = try Data(contentsOf: fileURL)
            let snapshot = try JSONDecoder().decode(LibraryInlineNoteDraftSnapshot.self, from: data)
            guard snapshot.recordID == recordID else { return nil }
            return snapshot
        }.value
    }

    static func write(_ snapshot: LibraryInlineNoteDraftSnapshot) async throws {
        try await Task.detached(priority: .utility) {
            let fileURL = try url(recordID: snapshot.recordID)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
        }.value
    }

    static func removeIfMatching(recordID: String, draftVersion: UInt64) async throws {
        try await Task.detached(priority: .utility) {
            let fileURL = try url(recordID: recordID)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let currentData = try Data(contentsOf: fileURL)
            let current = try JSONDecoder().decode(LibraryInlineNoteDraftSnapshot.self, from: currentData)
            guard current.recordID == recordID, current.draftVersion == draftVersion else { return }
            try FileManager.default.removeItem(at: fileURL)
        }.value
    }

    static func removeIfContentMatches(recordID: String, content: String) async throws {
        try await Task.detached(priority: .utility) {
            let fileURL = try url(recordID: recordID)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
            let currentData = try Data(contentsOf: fileURL)
            let current = try JSONDecoder().decode(LibraryInlineNoteDraftSnapshot.self, from: currentData)
            guard current.recordID == recordID, current.content == content else { return }
            try FileManager.default.removeItem(at: fileURL)
        }.value
    }
}

@MainActor
final class LibraryInlineNoteSaveService {
    static let shared = LibraryInlineNoteSaveService()

    typealias Commit = @MainActor (LibraryInlineNotePreparedSave?, String) throws -> String
    typealias Completion = @MainActor (Result<String, Error>) -> Void

    private struct Job {
        let snapshot: LibraryInlineNoteDraftSnapshot
        let basePayload: Data?
        let collection: String
        let updatedAt: Date
        let commit: Commit
        let draftWrite: Task<Void, Error>
        let completion: Completion
    }

    private var queues: [String: [Job]] = [:]
    private var workers: [String: Task<Void, Never>] = [:]
    private var draftWriters: [String: Task<Void, Error>] = [:]
    private var idleHandlers: [String: [@MainActor (Bool) -> Void]] = [:]
    private var nextDraftVersions: [String: UInt64] = [:]
    private var lastOutcomeByRecord: [String: Bool] = [:]
    private struct VersionChain {
        var knownVersions: Set<String>
        var latestVersion: String
    }
    private var committedVersionChains: [String: VersionChain] = [:]
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    func hasPending(recordID: String) -> Bool {
        workers[recordID] != nil || !(queues[recordID]?.isEmpty ?? true)
    }

    func markExistingContentConfirmed(recordID: String) {
        guard !hasPending(recordID: recordID) else { return }
        lastOutcomeByRecord[recordID] = true
    }

    func whenIdle(recordID: String, perform action: @escaping @MainActor (Bool) -> Void) {
        guard hasPending(recordID: recordID) else {
            action(lastOutcomeByRecord[recordID] ?? true)
            return
        }
        idleHandlers[recordID, default: []].append(action)
    }

    @discardableResult
    func enqueue(
        recordID: String,
        baseVersion: String,
        basePayload: Data?,
        collection: String = "",
        content: String,
        updatedAt: Date = .now,
        atLeastDraftVersion: UInt64 = 0,
        requiresBackgroundTime: Bool = false,
        commit: @escaping Commit,
        completion: @escaping Completion
    ) -> UInt64 {
        let revision = max(nextDraftVersions[recordID] ?? 0, atLeastDraftVersion) &+ 1
        nextDraftVersions[recordID] = revision
        let snapshot = LibraryInlineNoteDraftSnapshot(
            recordID: recordID,
            baseVersion: baseVersion,
            draftVersion: revision,
            content: content,
            updatedAt: updatedAt
        )
        let previousDraftWrite = draftWriters[recordID]
        let draftWrite = Task { @MainActor in
            if let previousDraftWrite {
                do {
                    try await previousDraftWrite.value
                } catch {
                    LibraryPerformanceLog.event(
                        "note.draft.previous-write.failed id=\(LibraryPerformanceLog.shortIdentifier(recordID)) error=\(error.localizedDescription)"
                    )
                }
            }
            try await LibraryInlineNoteDraftStorage.write(snapshot)
        }
        draftWriters[recordID] = draftWrite
        queues[recordID, default: []].append(
            Job(
                snapshot: snapshot,
                basePayload: basePayload,
                collection: collection,
                updatedAt: updatedAt,
                commit: commit,
                draftWrite: draftWrite,
                completion: completion
            )
        )
        if requiresBackgroundTime { beginBackgroundExecutionIfNeeded() }
        if workers[recordID] == nil {
            workers[recordID] = Task { await drain(recordID: recordID) }
        }
        return revision
    }

    private func drain(recordID: String) async {
        while var queue = queues[recordID], !queue.isEmpty {
            let job = queue.removeFirst()
            queues[recordID] = queue
            do {
                try await job.draftWrite.value
                await Task.yield()

                let prepared: LibraryInlineNotePreparedSave?
                if let basePayload = job.basePayload {
                    prepared = try await Self.prepare(
                        basePayload: basePayload,
                        collection: job.collection,
                        content: job.snapshot.content,
                        updatedAt: job.updatedAt
                    )
                } else {
                    prepared = nil
                }

                let expectedVersion: String
                if let chain = committedVersionChains[recordID],
                   chain.knownVersions.contains(job.snapshot.baseVersion) {
                    expectedVersion = chain.latestVersion
                } else {
                    expectedVersion = job.snapshot.baseVersion
                }
                let committedVersion = try job.commit(prepared, expectedVersion)
                var chain = committedVersionChains[recordID] ?? VersionChain(
                    knownVersions: [],
                    latestVersion: job.snapshot.baseVersion
                )
                chain.knownVersions.insert(job.snapshot.baseVersion)
                chain.knownVersions.insert(expectedVersion)
                chain.knownVersions.insert(committedVersion)
                chain.latestVersion = committedVersion
                committedVersionChains[recordID] = chain
                do {
                    try await LibraryInlineNoteDraftStorage.removeIfMatching(
                        recordID: recordID,
                        draftVersion: job.snapshot.draftVersion
                    )
                } catch {
                    LibraryPerformanceLog.event(
                        "note.draft.cleanup.failed id=\(LibraryPerformanceLog.shortIdentifier(recordID)) revision=\(job.snapshot.draftVersion) error=\(error.localizedDescription)"
                    )
                }
                lastOutcomeByRecord[recordID] = true
                job.completion(.success(committedVersion))
            } catch {
                lastOutcomeByRecord[recordID] = false
                job.completion(.failure(error))
            }
        }
        committedVersionChains[recordID] = nil
        workers[recordID] = nil
        queues[recordID] = nil
        draftWriters[recordID] = nil
        endBackgroundExecutionIfIdle()
        let handlers = idleHandlers.removeValue(forKey: recordID) ?? []
        let didSaveLatestVersion = lastOutcomeByRecord[recordID] ?? true
        handlers.forEach { $0(didSaveLatestVersion) }
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

private enum LibraryInlineNoteSavePreparationError: LocalizedError {
    case invalidPayload

    var errorDescription: String? {
        switch self {
        case .invalidPayload: "原题目数据无法解析，笔记未写入，也没有覆盖原记录。"
        }
    }
}
