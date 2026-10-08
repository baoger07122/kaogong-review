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

enum QuestionBankQuestionHeading {
    private static let internalClassification = "纯文字"
    private static let genericSubjects: Set<String> = ["行测", "行政职业能力测验", "公务员考试"]

    static func displayLabel(type: String, subject: String, moduleTitle: String? = nil) -> String? {
        let normalizedType = type.trimmingCharacters(in: .whitespacesAndNewlines)
        let comparableModule = QuestionBankModuleTitle.normalized(moduleTitle)
        let comparableType = QuestionBankModuleTitle.normalized(normalizedType)
        if !normalizedType.isEmpty, normalizedType != internalClassification,
           comparableType != comparableModule, !genericSubjects.contains(comparableType) {
            return normalizedType
        }

        let normalizedSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let comparableSubject = QuestionBankModuleTitle.normalized(normalizedSubject)
        guard !normalizedSubject.isEmpty, normalizedSubject != internalClassification,
              comparableSubject != comparableModule,
              !genericSubjects.contains(comparableSubject) else { return nil }
        return normalizedSubject
    }
}

enum QuestionBankTypography {
    static let contentFont = Font.system(size: 16, weight: .regular)
    static let contentLineSpacing: CGFloat = 6
}

enum QuestionBankReaderPreferences {
    static let confirmAnswerAfterSelectionKey = "question-bank.confirm-answer-after-selection"
    static let presentationModeKey = "question-bank.presentation-mode"
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
    static func isHorizontalIntent(
        horizontal: CGFloat,
        vertical: CGFloat,
        minimumDistance: CGFloat = 8
    ) -> Bool {
        abs(horizontal) >= minimumDistance && abs(horizontal) > abs(vertical) * 1.2
    }

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

struct QuestionBankInteractivePageDeck<PageID: Hashable, Page: View>: View {
    let currentID: PageID
    let previousID: PageID?
    let nextID: PageID?
    let isEnabled: Bool
    let onCommit: (Int) -> Void
    private let page: (PageID, Bool) -> Page
    @State private var dragOffset: CGFloat = 0
    @State private var isCommitting = false
    @State private var isHorizontalPagingDrag = false
    @State private var commitTask: Task<Void, Never>?

    init(
        currentID: PageID,
        previousID: PageID?,
        nextID: PageID?,
        isEnabled: Bool,
        onCommit: @escaping (Int) -> Void,
        @ViewBuilder page: @escaping (PageID, Bool) -> Page
    ) {
        self.currentID = currentID
        self.previousID = previousID
        self.nextID = nextID
        self.isEnabled = isEnabled
        self.onCommit = onCommit
        self.page = page
    }

    private var previewID: PageID? {
        guard abs(dragOffset) > 0 else { return nil }
        return dragOffset < 0 ? nextID : previousID
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let previewID {
                    page(previewID, isHorizontalPagingDrag)
                        .offset(x: dragOffset < 0 ? geometry.size.width + dragOffset : -geometry.size.width + dragOffset)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                page(currentID, isHorizontalPagingDrag)
                    .offset(x: dragOffset)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .onChanged { value in
                        guard isEnabled, !isCommitting else { return }
                        let horizontal = value.translation.width
                        let vertical = value.translation.height
                        guard QuestionBankHorizontalSwipe.isHorizontalIntent(
                            horizontal: horizontal,
                            vertical: vertical
                        ) else { return }
                        isHorizontalPagingDrag = true
                        let width = max(1, geometry.size.width)
                        if horizontal < 0 {
                            dragOffset = nextID == nil
                                ? max(-28, horizontal * 0.16)
                                : max(-width, horizontal)
                        } else {
                            dragOffset = previousID == nil
                                ? min(28, horizontal * 0.16)
                                : min(width, horizontal)
                        }
                    }
                    .onEnded { value in
                        guard isEnabled, !isCommitting,
                              let direction = QuestionBankHorizontalSwipe.direction(
                                horizontal: value.translation.width,
                                vertical: value.translation.height
                              ) else {
                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                                dragOffset = 0
                            }
                            releaseHorizontalLockAfterRebound()
                            return
                        }
                        guard direction > 0 ? nextID != nil : previousID != nil else {
                            withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                                dragOffset = 0
                            }
                            releaseHorizontalLockAfterRebound()
                            return
                        }
                        isCommitting = true
                        withAnimation(.interactiveSpring(response: 0.24, dampingFraction: 0.86)) {
                            dragOffset = direction > 0 ? -geometry.size.width : geometry.size.width
                        }
                        commitTask?.cancel()
                        commitTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 260_000_000)
                            guard !Task.isCancelled else { return }
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) {
                                onCommit(direction)
                                dragOffset = 0
                                isCommitting = false
                                isHorizontalPagingDrag = false
                            }
                        }
                    }
            )
        }
        .onChange(of: currentID) { _, _ in
            if !isCommitting {
                dragOffset = 0
                isHorizontalPagingDrag = false
            }
        }
        .onDisappear { commitTask?.cancel() }
    }

    private func releaseHorizontalLockAfterRebound() {
        guard isHorizontalPagingDrag else { return }
        commitTask?.cancel()
        commitTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            guard !Task.isCancelled else { return }
            isHorizontalPagingDrag = false
        }
    }
}

struct QuestionBankPageTransitionMotion: Equatable {
    enum Edge: Equatable {
        case leading
        case trailing
    }

    let insertion: Edge
    let removal: Edge
}

enum QuestionBankPageTransition {
    /// A positive direction is next: the new page enters from trailing as the old page exits leading.
    static func motion(for direction: Int) -> QuestionBankPageTransitionMotion {
        if direction < 0 {
            return QuestionBankPageTransitionMotion(insertion: .leading, removal: .trailing)
        }
        return QuestionBankPageTransitionMotion(insertion: .trailing, removal: .leading)
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
