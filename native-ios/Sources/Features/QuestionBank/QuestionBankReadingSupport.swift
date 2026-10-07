import Foundation
import SwiftData
import SwiftUI

enum QuestionBankReadingMode: String, CaseIterable, Identifiable {
    case reading
    case practice

    var id: String { rawValue }
    var title: String { self == .reading ? "看题" : "刷题" }

    func revealsAnswer(
        afterSelecting optionID: String?,
        wasConfirmed: Bool,
        requiresConfirmation: Bool = false
    ) -> Bool {
        self == .reading || (optionID != nil && (!requiresConfirmation || wasConfirmed))
    }
}

enum QuestionBankReaderPreferences {
    static let confirmAnswerAfterSelectionKey = "question-bank.confirm-answer-after-selection"
}

struct QuestionBankDoodleMemoryCache {
    private let capacity: Int
    private var drawings: [String: String] = [:]
    private var leastToMostRecent: [String] = []

    init(capacity: Int = 4) {
        self.capacity = max(1, capacity)
    }

    mutating func drawingData(for recordID: String) -> String? {
        guard let data = drawings[recordID] else { return nil }
        leastToMostRecent.removeAll { $0 == recordID }
        leastToMostRecent.append(recordID)
        return data
    }

    mutating func store(_ data: String, for recordID: String) {
        drawings[recordID] = data
        leastToMostRecent.removeAll { $0 == recordID }
        leastToMostRecent.append(recordID)
        while leastToMostRecent.count > capacity {
            let evicted = leastToMostRecent.removeFirst()
            drawings.removeValue(forKey: evicted)
        }
    }

    mutating func invalidate() {
        drawings.removeAll()
        leastToMostRecent.removeAll()
    }
}

enum QuestionBankHorizontalSwipe {
    /// Returns 1 for a left swipe (next), -1 for a right swipe (previous).
    static func direction(
        horizontal: CGFloat,
        vertical: CGFloat,
        minimumDistance: CGFloat = 56
    ) -> Int? {
        guard abs(horizontal) >= minimumDistance,
              abs(horizontal) > abs(vertical) * 1.25 else { return nil }
        return horizontal < 0 ? 1 : -1
    }
}

enum QuestionBankPresentationMode: String, CaseIterable, Identifiable, Equatable {
    case continuous
    case single

    var id: String { rawValue }
    var title: String { self == .continuous ? "连续阅读" : "单题模式" }
    var shortTitle: String { self == .continuous ? "连续" : "单题" }
}

struct QuestionBankReaderPosition: Equatable {
    var presentationMode: QuestionBankPresentationMode
    var currentQuestionID: String?
    var splitMaterialID: String?
}

enum QuestionBankReaderTransition {
    static func switchingPresentation(
        to mode: QuestionBankPresentationMode,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.presentationMode = mode
        return result
    }

    static func selectingOverviewQuestion(
        _ questionID: String,
        materialID: String?,
        availableMaterialIDs: Set<String>,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.presentationMode = .single
        result.currentQuestionID = questionID
        if position.splitMaterialID != nil {
            result.splitMaterialID = materialID.flatMap { availableMaterialIDs.contains($0) ? $0 : nil }
        }
        return result
    }

    static func movingToQuestion(
        _ questionID: String,
        materialID: String?,
        availableMaterialIDs: Set<String>,
        from position: QuestionBankReaderPosition
    ) -> QuestionBankReaderPosition {
        var result = position
        result.currentQuestionID = questionID
        if position.splitMaterialID != nil {
            result.splitMaterialID = materialID.flatMap { availableMaterialIDs.contains($0) ? $0 : nil }
        }
        return result
    }

    static func adjacentQuestionID(
        currentID: String?,
        orderedIDs: [String],
        direction: Int
    ) -> String? {
        guard direction == -1 || direction == 1,
              let currentID,
              let index = orderedIDs.firstIndex(of: currentID) else { return nil }
        let targetIndex = index + direction
        guard orderedIDs.indices.contains(targetIndex) else { return nil }
        return orderedIDs[targetIndex]
    }

    static func displayedQuestionIDs(
        for mode: QuestionBankPresentationMode,
        currentID: String?,
        orderedIDs: [String]
    ) -> [String] {
        guard mode == .single else { return orderedIDs }
        if let currentID, orderedIDs.contains(currentID) { return [currentID] }
        return orderedIDs.first.map { [$0] } ?? []
    }

    static func ordinal(of questionID: String?, in orderedIDs: [String]) -> Int? {
        guard let questionID, let index = orderedIDs.firstIndex(of: questionID) else { return nil }
        return index + 1
    }
}

enum QuestionBankSelectedOptionsStorage {
    static func decode(_ value: String) -> [String: String] {
        guard let data = value.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    static func encode(_ selections: [String: String]) -> String {
        guard let data = try? JSONEncoder().encode(selections),
              let value = String(data: data, encoding: .utf8) else { return "{}" }
        return value
    }
}

enum QuestionBankRevealedAnswersStorage {
    static func decode(_ value: String) -> Set<String> {
        guard let data = value.data(using: .utf8) else { return [] }
        return Set((try? JSONDecoder().decode([String].self, from: data)) ?? [])
    }

    static func encode(_ questionIDs: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(questionIDs.sorted()),
              let value = String(data: data, encoding: .utf8) else { return "[]" }
        return value
    }
}

struct QuestionBankDoodleToolbarTarget: Equatable {
    let questionID: String
    let questionNumber: Int
    let materialID: String?

    static func resolve(
        visibleQuestionID: String?,
        questions: [QuestionBankQuestion],
        materialIDs: Set<String>
    ) -> QuestionBankDoodleToolbarTarget? {
        guard let visibleQuestionID,
              let question = questions.first(where: { $0.id == visibleQuestionID }) else { return nil }
        let materialID = !question.materialID.isEmpty && materialIDs.contains(question.materialID)
            ? question.materialID : nil
        return QuestionBankDoodleToolbarTarget(
            questionID: question.id, questionNumber: question.number, materialID: materialID
        )
    }
}

enum QuestionBankSplitOrientation: Equatable {
    case landscape
    case portrait
}

enum QuestionBankSplitLayout {
    static let minimumQuestionPaneWidth: CGFloat = 420
    static let landscapeSplitMinimumWidth: CGFloat = 960

    static func orientation(width: CGFloat, height: CGFloat) -> QuestionBankSplitOrientation {
        width >= landscapeSplitMinimumWidth && width > height ? .landscape : .portrait
    }

    static func materialWidth(totalWidth: CGFloat) -> CGFloat {
        min(totalWidth * 0.555, totalWidth - minimumQuestionPaneWidth - 1)
    }

    static func materialHeight(totalHeight: CGFloat) -> CGFloat {
        min(max(totalHeight * 0.55, 300), max(totalHeight - 260, 0))
    }
}

enum QuestionBankOptionDisplay {
    static func text(for option: QuestionBankOption) -> String? {
        let text = option.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, text != option.id else { return nil }
        return text
    }
}

enum QuestionBankDoodleScope: Equatable {
    case question(String)
    case material(String)

    fileprivate var kind: String {
        switch self {
        case .question: "question"
        case .material: "material"
        }
    }

    fileprivate var stableID: String {
        switch self {
        case .question(let id), .material(let id): id
        }
    }
}

enum QuestionBankDoodleRepository {
    static let collection = "keyvalue"
    static let recordIDPrefix = "question_bank_doodle_v1_"

    static func recordID(paperID: String, scope: QuestionBankDoodleScope) -> String {
        let identity = "\(paperID)\u{0}\(scope.kind)\u{0}\(scope.stableID)"
        let encoded = Data(identity.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return recordIDPrefix + encoded
    }

    static func isDoodleRecordID(_ recordID: String?) -> Bool {
        recordID?.hasPrefix(recordIDPrefix) == true
    }

    static func drawingData(recordID: String, context: ModelContext) throws -> String {
        let totalStart = ProcessInfo.processInfo.systemUptime
        let fetchStart = ProcessInfo.processInfo.systemUptime
        let descriptor = descriptor(for: recordID)
        let record: StoredRecord?
        do {
            record = try context.fetch(descriptor).first
        } catch {
            LibraryPerformanceLog.mark("doodle.read.fetch", since: fetchStart)
            LibraryPerformanceLog.mark("doodle.read.total", since: totalStart)
            throw error
        }
        LibraryPerformanceLog.mark("doodle.read.fetch", since: fetchStart)
        guard let record else {
            LibraryPerformanceLog.mark("doodle.read.total", since: totalStart)
            return ""
        }
        let payloadStart = ProcessInfo.processInfo.systemUptime
        guard let object = record.jsonObject,
              object["format"] as? String == recordIDPrefix,
              let data = object["pencilKitData"] as? String else {
            LibraryPerformanceLog.mark("doodle.read.payload", since: payloadStart)
            LibraryPerformanceLog.mark("doodle.read.total", since: totalStart)
            throw QuestionBankDoodleError.invalidSavedDrawing
        }
        LibraryPerformanceLog.mark("doodle.read.payload", since: payloadStart)
        LibraryPerformanceLog.mark("doodle.read.total", since: totalStart)
        return data
    }

    @MainActor
    @discardableResult
    static func save(
        recordID: String,
        drawingData: String,
        context: ModelContext
    ) -> String? {
        let totalStart = ProcessInfo.processInfo.systemUptime
        do {
            let descriptor = descriptor(for: recordID)
            let fetchStart = ProcessInfo.processInfo.systemUptime
            let existing = try context.fetch(descriptor).first
            LibraryPerformanceLog.mark("doodle.save.fetch", since: fetchStart)
            if drawingData.isEmpty {
                guard let existing else {
                    LibraryPerformanceLog.mark("doodle.save.skipped-empty", since: totalStart)
                    return nil
                }
                context.delete(existing)
                let contextSaveStart = ProcessInfo.processInfo.systemUptime
                try context.save()
                LibraryPerformanceLog.mark("doodle.save.context", since: contextSaveStart)
                LibraryPerformanceLog.mark("doodle.save.total", since: totalStart)
                return nil
            }
            if let existing,
               existing.jsonObject?["pencilKitData"] as? String == drawingData {
                LibraryPerformanceLog.mark("doodle.save.skipped-unchanged", since: totalStart)
                return nil
            }

            let now = Date()
            let object: [String: Any] = [
                "id": recordID,
                "key": recordID,
                "format": recordIDPrefix,
                "pencilKitData": drawingData,
                "updatedAt": ISO8601DateFormatter().string(from: now)
            ]
            let payloadStart = ProcessInfo.processInfo.systemUptime
            let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            LibraryPerformanceLog.mark("doodle.save.payload", since: payloadStart)
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = now
            } else {
                context.insert(StoredRecord(
                    collection: collection,
                    recordID: recordID,
                    payload: payload,
                    subject: "真题涂鸦",
                    createdAt: now,
                    updatedAt: now
                ))
            }
            let contextSaveStart = ProcessInfo.processInfo.systemUptime
            try context.save()
            LibraryPerformanceLog.mark("doodle.save.context", since: contextSaveStart)
            LibraryPerformanceLog.mark("doodle.save.total", since: totalStart)
            return nil
        } catch {
            LibraryPerformanceLog.mark("doodle.save.failed", since: totalStart)
            return "涂鸦未保存：\(error.localizedDescription)"
        }
    }

    private static func descriptor(for recordID: String) -> FetchDescriptor<StoredRecord> {
        let collectionName = Self.collection
        return FetchDescriptor<StoredRecord>(
            predicate: #Predicate { $0.collection == collectionName && $0.recordID == recordID }
        )
    }
}

enum QuestionBankDoodleError: LocalizedError {
    case invalidSavedDrawing

    var errorDescription: String? {
        "已保存的真题涂鸦记录格式无效，原记录未修改。"
    }
}

struct QuestionBankDoodleAutosaveObserver: View {
    @ObservedObject private var session: LibraryDoodleSession
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    private let context: ModelContext
    private let onSaved: (String, String, String?) -> Void

    init(
        session: LibraryDoodleSession,
        context: ModelContext,
        onSaved: @escaping (String, String, String?) -> Void = { _, _, _ in }
    ) {
        _session = ObservedObject(wrappedValue: session)
        _canvas = ObservedObject(wrappedValue: session.canvas)
        self.context = context
        self.onSaved = onSaved
    }

    var body: some View {
        Color.clear
            .onChange(of: canvas.drawingData) { _, drawingData in
                guard session.isPresented,
                      let recordID = session.targetRecordID,
                      QuestionBankDoodleRepository.isDoodleRecordID(recordID) else { return }
                let error = QuestionBankDoodleRepository.save(
                    recordID: recordID,
                    drawingData: drawingData,
                    context: context
                )
                session.saveError = error
                onSaved(recordID, drawingData, error)
            }
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }
}
