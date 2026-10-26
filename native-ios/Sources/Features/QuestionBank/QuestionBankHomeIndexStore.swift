import Foundation
import SwiftData
import SwiftUI

@MainActor
final class QuestionBankHomeIndexStore: ObservableObject {
    @Published private(set) var index: QuestionBankHomeIndex?
    @Published private(set) var isLoading = false

    private var activeLoadID: UUID?

    func load(records: [QuestionBankRecord], revision: [QuestionBankHomeIndexRevision]) async {
        if index?.revision == revision {
            isLoading = false
            NativePerformanceLog.event("question-bank index cache hit records=\(revision.count)")
            return
        }
        let loadID = UUID()
        activeLoadID = loadID
        isLoading = true

        let inputStarted = ProcessInfo.processInfo.systemUptime
        let inputs = records.map(QuestionBankHomeIndexInput.init)
        NativePerformanceLog.mark("question-bank index input records=\(inputs.count)", since: inputStarted)

        let decodeStarted = ProcessInfo.processInfo.systemUptime
        let snapshot = await Task.detached(priority: .userInitiated) {
            QuestionBankHomeIndexSnapshot.build(records: inputs)
        }.value

        guard activeLoadID == loadID else { return }
        guard !Task.isCancelled else {
            isLoading = false
            activeLoadID = nil
            return
        }
        guard QuestionBankHomeIndexRevision.make(records: records) == revision else {
            isLoading = false
            activeLoadID = nil
            return
        }

        index = QuestionBankHomeIndex(snapshot: snapshot, records: records)
        isLoading = false
        activeLoadID = nil
        NativePerformanceLog.mark("question-bank index decode records=\(inputs.count)", since: decodeStarted)
    }
}
