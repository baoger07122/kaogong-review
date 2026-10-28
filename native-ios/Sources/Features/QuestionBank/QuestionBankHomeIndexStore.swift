import Foundation
import SwiftData
import SwiftUI

@MainActor
final class QuestionBankHomeIndexStore: ObservableObject {
    @Published private(set) var index: QuestionBankHomeIndex?
    @Published private(set) var isLoading = false
    @Published private(set) var requestGeneration = 0
    @Published private(set) var loadedGeneration: Int?

    private var activeLoadID: UUID?
    private var activeSnapshotTask: Task<QuestionBankHomeIndexSnapshot?, Never>?
    private var filteredResultCache: (
        generation: Int,
        filter: QuestionBankHomeFilter,
        result: QuestionBankHomeFilterResult
    )?

    var isCurrent: Bool {
        index != nil && loadedGeneration == requestGeneration
    }

    func requestReload() {
        activeLoadID = nil
        activeSnapshotTask?.cancel()
        activeSnapshotTask = nil
        isLoading = false
        requestGeneration &+= 1
    }

    func cancelLoad() {
        activeLoadID = nil
        activeSnapshotTask?.cancel()
        activeSnapshotTask = nil
        isLoading = false
    }

    func filtered(matching filter: QuestionBankHomeFilter) -> QuestionBankHomeFilterResult? {
        guard isCurrent, let index else { return nil }
        if let cached = filteredResultCache,
           cached.generation == requestGeneration, cached.filter == filter {
            return cached.result
        }

        let started = ProcessInfo.processInfo.systemUptime
        let result = index.filtered(matching: filter)
        filteredResultCache = (requestGeneration, filter, result)
        NativePerformanceLog.mark(
            "question-bank filter snapshot papers=\(result.visiblePapers.count) questions=\(result.totalQuestionCount)",
            since: started
        )
        return result
    }

    /// Compatibility entry point used by index unit tests. The expected revision
    /// is checked against the detached snapshot, avoiding a second model-table scan.
    func load(records: [QuestionBankRecord], revision: [QuestionBankHomeIndexRevision]) async {
        requestReload()
        await load(records: records, generation: requestGeneration, expectedRevision: revision)
    }

    func load(records: [QuestionBankRecord], generation: Int) async {
        await load(records: records, generation: generation, expectedRevision: nil)
    }

    private func load(
        records: [QuestionBankRecord],
        generation: Int,
        expectedRevision: [QuestionBankHomeIndexRevision]?
    ) async {
        guard generation == requestGeneration else { return }
        if let expectedRevision, index?.revision == expectedRevision {
            activeLoadID = nil
            activeSnapshotTask?.cancel()
            activeSnapshotTask = nil
            loadedGeneration = generation
            isLoading = false
            filteredResultCache = nil
            NativePerformanceLog.event("question-bank index cache hit records=\(expectedRevision.count)")
            return
        }
        if expectedRevision == nil, loadedGeneration == generation, index != nil {
            isLoading = false
            return
        }

        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true

        let inputStarted = ProcessInfo.processInfo.systemUptime
        let inputs = records.map(QuestionBankHomeIndexInput.init)
        NativePerformanceLog.mark("question-bank index main-thread input records=\(inputs.count)", since: inputStarted)

        let snapshotStarted = ProcessInfo.processInfo.systemUptime
        let snapshotTask = Task.detached(priority: .userInitiated) {
            QuestionBankHomeIndexSnapshot.buildCancellable(records: inputs)
        }
        activeSnapshotTask = snapshotTask
        let snapshot = await snapshotTask.value

        guard activeLoadID == loadID, generation == requestGeneration else { return }
        guard !Task.isCancelled, let snapshot else {
            isLoading = false
            activeLoadID = nil
            activeSnapshotTask = nil
            return
        }
        if let expectedRevision, snapshot.revision != expectedRevision {
            isLoading = false
            activeLoadID = nil
            activeSnapshotTask = nil
            return
        }

        let materializeStarted = ProcessInfo.processInfo.systemUptime
        index = QuestionBankHomeIndex(snapshot: snapshot, records: records)
        NativePerformanceLog.mark("question-bank index main-thread materialize records=\(inputs.count)", since: materializeStarted)
        filteredResultCache = nil
        loadedGeneration = generation
        isLoading = false
        activeLoadID = nil
        activeSnapshotTask = nil
        NativePerformanceLog.mark("question-bank index background snapshot records=\(inputs.count)", since: snapshotStarted)
    }
}
