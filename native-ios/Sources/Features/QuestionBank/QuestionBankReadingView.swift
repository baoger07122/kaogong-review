import Foundation
import SwiftUI
import SwiftData
import UIKit
import ImageIO

struct QuestionBankReadingStep: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case material(String)
        case question(String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .material(let id): "material:\(id)"
        case .question(let id): "question:\(id)"
        }
    }
}

enum QuestionBankReadingSequence {
    static func steps(for questions: [QuestionBankQuestion]) -> [QuestionBankReadingStep] {
        let orderedQuestions = questions.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id < $1.id
        }
        var emittedMaterialIDs = Set<String>()
        var result: [QuestionBankReadingStep] = []
        result.reserveCapacity(orderedQuestions.count * 2)

        for question in orderedQuestions {
            if !question.materialID.isEmpty, emittedMaterialIDs.insert(question.materialID).inserted {
                result.append(QuestionBankReadingStep(kind: .material(question.materialID)))
            }
            result.append(QuestionBankReadingStep(kind: .question(question.id)))
        }
        return result
    }
}

struct QuestionBankQuestionRouteTarget: Equatable {
    let moduleID: String
    let questionNumber: Int
}

enum QuestionBankQuestionRoute {
    static func target(
        questionNumber: Int?,
        paperID: String,
        selectedModuleTitle: String,
        records: [QuestionBankRecord]
    ) -> QuestionBankQuestionRouteTarget? {
        guard let questionNumber, questionNumber > 0 else { return nil }
        let candidates = records
            .filter {
                $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind
                    && $0.questionNumber == questionNumber
            }
            .sorted { $0.stableID < $1.stableID }
        for question in candidates {
            guard let moduleID = question.moduleID, !moduleID.isEmpty else { continue }
            if !selectedModuleTitle.isEmpty {
                let moduleMatchesFilter = records.contains {
                    $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind
                        && $0.stableID == moduleID && $0.title == selectedModuleTitle
                }
                guard moduleMatchesFilter else { continue }
            }
            return QuestionBankQuestionRouteTarget(moduleID: moduleID, questionNumber: questionNumber)
        }
        return nil
    }
}

struct QuestionBankOverviewItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let materialID: String
    let type: String
    let stem: String
    let stemImageAssetID: String

    var materialGroupLabel: String? {
        materialID.isEmpty ? nil : "共用材料组"
    }
}

private struct QuestionBankReadingItem: Identifiable {
    var record: QuestionBankRecord
    var question: QuestionBankQuestion
    let moduleTitle: String?
    let moduleSequence: Int
    var isLoaded = false
    var localOrdinal = 0

    var id: String { record.stableID }
    var overviewItem: QuestionBankOverviewItem {
        QuestionBankOverviewItem(
            id: id,
            number: question.number,
            materialID: question.materialID,
            type: QuestionBankQuestionHeading.displayLabel(
                type: question.type,
                subject: question.subject,
                moduleTitle: moduleTitle
            ) ?? "",
            stem: question.stem,
            stemImageAssetID: question.stemImageAssetID
        )
    }
}

private struct QuestionBankReaderSheet: Identifiable {
    let id = UUID()

    enum Content {
        case overview
        case material(String)
        case questionDetail(String)
    }

    let content: Content
}

private struct QuestionBankScrollRequest: Equatable {
    let questionID: String
    let token: UUID
}

private struct QuestionBankReaderViewportFrame: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

private struct QuestionBankReaderViewportPreference: PreferenceKey {
    static var defaultValue: [String: QuestionBankReaderViewportFrame] = [:]

    static func reduce(
        value: inout [String: QuestionBankReaderViewportFrame],
        nextValue: () -> [String: QuestionBankReaderViewportFrame]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct QuestionBankModuleView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootTabSelection) private var rootTabSelection
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @StateObject private var readerDirectoryStore = QuestionBankReaderDirectoryStore()
    @StateObject private var readerWindowStore = QuestionBankReaderWindowStore()
    @StateObject private var answerStateStore = QuestionBankAnswerStateStore.shared

    let paperID: String
    let moduleID: String
    let initialQuestionNumber: String

    @State private var readingItems: [QuestionBankReadingItem] = []
    @State private var readingSteps: [QuestionBankReadingStep] = []
    @State private var materialsByID: [String: QuestionBankMaterial] = [:]
    @State private var assetsByID: [String: QuestionBankAssetReference] = [:]
    @State private var activeSheet: QuestionBankReaderSheet?
    @State private var showsReaderOptions = false
    @State private var continuousAnchorQuestionID: String?
    @State private var pendingOverviewQuestionID: String?
    @State private var continuousScrollRequest: QuestionBankScrollRequest?
    @State private var splitScrollRequest: QuestionBankScrollRequest?
    @State private var snapshotRevision = 0
    @State private var loadedDirectoryVersion: QuestionBankCatalogDataVersion?
    @State private var cachedModule: QuestionBankModule?
    @State private var isReaderRouteVisible = false
    @State private var isReaderVisible = false
    @State private var needsReaderRefresh = true
    @State private var readerSnapshotGeneration = 0
    @State private var readerQuestionUpdateGeneration = 0
    @State private var pendingReaderQuestionIDs = Set<String>()
    @State private var reloadReaderWindowAfterQuestionUpdate = false
    @State private var isReaderLoading = false
    @State private var readerLoadError: String?
    @State private var continuousQuestionDoodleRecordID: String?
    @State private var didApplyInitialFocus = false
    @State private var didApplyAutomaticDataAnalysisSplit = false
    @State private var missingAnswerEditError: String?
    @State private var missingAnswerEditConfirmation: String?
    @SceneStorage private var storedSplitMaterialID: String
    @SceneStorage private var storedQuestionID: String
    @SceneStorage private var storedReadingMode: String
    @AppStorage(QuestionBankReaderPreferences.presentationModeKey)
    private var storedPresentationMode = QuestionBankPresentationMode.continuous.rawValue
    @SceneStorage private var storedSelectedOptionsJSON: String
    @SceneStorage private var storedRevealedAnswersJSON: String
    private let legacySelectedOptionsStorageKey: String
    private let legacyRevealedAnswersStorageKey: String
    @AppStorage(QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey)
    private var requiresAnswerConfirmation = false

    init(paperID: String, moduleID: String, initialQuestionNumber: String) {
        self.paperID = paperID
        self.moduleID = moduleID
        self.initialQuestionNumber = initialQuestionNumber
        _storedSplitMaterialID = SceneStorage(
            wrappedValue: "",
            "question-bank.split.\(paperID).\(moduleID)"
        )
        _storedQuestionID = SceneStorage(
            wrappedValue: "",
            "question-bank.question.\(paperID).\(moduleID)"
        )
        _storedReadingMode = SceneStorage(
            wrappedValue: QuestionBankReadingMode.practice.rawValue,
            "question-bank.mode.v2.\(paperID).\(moduleID)"
        )
        let selectedOptionsKey = "question-bank.selected-options.\(paperID).\(moduleID)"
        let revealedAnswersKey = "question-bank.revealed-answers.\(paperID).\(moduleID)"
        legacySelectedOptionsStorageKey = selectedOptionsKey
        legacyRevealedAnswersStorageKey = revealedAnswersKey
        _storedSelectedOptionsJSON = SceneStorage(
            wrappedValue: "{}",
            selectedOptionsKey
        )
        _storedRevealedAnswersJSON = SceneStorage(
            wrappedValue: "[]",
            revealedAnswersKey
        )
    }

    private var module: QuestionBankModule? { cachedModule }

    private var initialFocusQuestionID: String? {
        guard let number = Int(initialQuestionNumber), number > 0 else { return nil }
        return readingItems.first { $0.question.number == number }?.id
    }

    private var sourcePapers: [QuestionBankSourcePaper] {
        readerWindowStore.sourcePapersByID[paperID] ?? []
    }

    private var splitMaterialID: String? {
        get { storedSplitMaterialID.isEmpty ? nil : storedSplitMaterialID }
        nonmutating set { storedSplitMaterialID = newValue ?? "" }
    }

    private var currentVisibleQuestionID: String? {
        get { storedQuestionID.isEmpty ? nil : storedQuestionID }
        nonmutating set { storedQuestionID = newValue ?? "" }
    }

    private var readingMode: QuestionBankReadingMode {
        get { QuestionBankReadingMode(rawValue: storedReadingMode) ?? .practice }
        nonmutating set { storedReadingMode = newValue.rawValue }
    }

    private var presentationMode: QuestionBankPresentationMode {
        get { QuestionBankPresentationMode(rawValue: storedPresentationMode) ?? .continuous }
        nonmutating set { storedPresentationMode = newValue.rawValue }
    }

    private func selectedAnswerOption(for compoundID: String) -> String? {
        answerStateStore.value(for: compoundID)?.selectedOptionID
    }

    private func isAnswerRevealed(_ compoundID: String) -> Bool {
        answerStateStore.value(for: compoundID)?.isRevealed == true
    }

    private var readerPosition: QuestionBankReaderPosition {
        QuestionBankReaderPosition(
            presentationMode: presentationMode,
            currentQuestionID: currentVisibleQuestionID,
            splitMaterialID: splitMaterialID
        )
    }

    private var currentSingleItem: QuestionBankReadingItem? {
        let questionID = QuestionBankReaderTransition.displayedQuestionIDs(
            for: .single, currentID: currentVisibleQuestionID, orderedIDs: orderedQuestionIDs
        ).first
        return questionID.flatMap { readingItem(for: $0) } ?? readingItems.first
    }

    private var orderedQuestionIDs: [String] { readingItems.map(\.id) }

    private var directoryMaterialIDs: Set<String> {
        Set(readingItems.map(\.question.materialID).filter { !$0.isEmpty })
    }

    private var singlePositionText: String {
        let ordinal = QuestionBankReaderTransition.ordinal(of: currentVisibleQuestionID, in: orderedQuestionIDs) ?? 1
        return "\(ordinal)/\(orderedQuestionIDs.count)"
    }

    private func activateReaderIfNeeded() {
        let shouldBeVisible = isReaderRouteVisible && rootTabSelection.wrappedValue == .questionBank
        isReaderVisible = shouldBeVisible
        guard shouldBeVisible, needsReaderRefresh else { return }
        readerSnapshotGeneration &+= 1
    }

    private func requestReaderSnapshot() {
        needsReaderRefresh = true
        pendingReaderQuestionIDs.removeAll()
        readerQuestionUpdateGeneration &+= 1
        loadedDirectoryVersion = nil
        readerWindowStore.cancel(clear: true)
        materialsByID = [:]
        assetsByID = [:]
        readerDirectoryStore.cancel(clear: true)
        guard isReaderVisible, rootTabSelection.wrappedValue == .questionBank else { return }
        readerSnapshotGeneration &+= 1
    }

    private func requestReaderQuestionUpdates(_ questionIDs: Set<String>) {
        guard !questionIDs.isEmpty else { return }
        guard isReaderVisible, rootTabSelection.wrappedValue == .questionBank else {
            needsReaderRefresh = true
            return
        }
        guard !needsReaderRefresh, !readingItems.isEmpty else {
            requestReaderSnapshot()
            return
        }
        if readerWindowStore.isLoading {
            reloadReaderWindowAfterQuestionUpdate = true
            readerWindowStore.cancel(clear: false)
        }
        pendingReaderQuestionIDs.formUnion(questionIDs)
        readerQuestionUpdateGeneration &+= 1
    }

    private func loadReaderSnapshot(generation: Int) async {
        guard isReaderVisible, rootTabSelection.wrappedValue == .questionBank,
              needsReaderRefresh || loadedDirectoryVersion == nil else { return }
        isReaderLoading = true
        readerLoadError = nil
        await readerDirectoryStore.loadModule(
            container: modelContext.container,
            paperID: paperID,
            moduleID: moduleID
        )
        guard !Task.isCancelled,
              readerSnapshotGeneration == generation,
              isReaderVisible,
              rootTabSelection.wrappedValue == .questionBank else { return }
        guard let directory = readerDirectoryStore.directory else {
            isReaderLoading = false
            needsReaderRefresh = true
            readerLoadError = readerDirectoryStore.errorMessage ?? "题目目录暂不可用。"
            return
        }
        guard directory.catalogVersion != loadedDirectoryVersion else {
            isReaderLoading = false
            needsReaderRefresh = false
            return
        }

        let summary = directory.moduleSummariesByPaperAndID["\(paperID)::\(moduleID)"]
        cachedModule = summary.map {
            QuestionBankModule(
                id: $0.moduleID,
                paperID: $0.paperID,
                sequence: $0.sequence,
                title: $0.title,
                instruction: "",
                originalPage: ""
            )
        }
        readingItems = directory.questions.map { entry in
            let question = QuestionBankQuestion(
                id: entry.questionID,
                paperID: entry.paperID,
                moduleID: entry.moduleID,
                number: entry.originalNumber,
                subject: entry.coarseModule,
                type: entry.coarseQuestionType,
                materialID: entry.materialID,
                stem: "",
                stemImageAssetID: "",
                options: [],
                answer: "",
                explanation: "",
                originalPage: "",
                isDifficult: entry.isDifficult,
                needsReview: entry.needsReview,
                knowledgePoints: entry.knowledgePoints,
                weaknessTags: entry.weaknessTags
            )
            let record = QuestionBankRecord(
                compoundID: entry.sourceCompoundID,
                paperID: entry.paperID,
                kind: QuestionBankRepository.questionKind,
                stableID: entry.questionID,
                moduleID: entry.moduleID,
                questionNumber: entry.originalNumber,
                sequence: entry.moduleSequence,
                title: entry.paperTitle,
                payload: Data(),
                contentRevision: entry.sourceRevision
            )
            return QuestionBankReadingItem(
                record: record,
                question: question,
                moduleTitle: entry.moduleTitle,
                moduleSequence: entry.moduleSequence,
                isLoaded: false,
                localOrdinal: entry.localOrdinal
            )
        }
        readingSteps = QuestionBankReadingSequence.steps(for: readingItems.map(\.question))
        materialsByID = [:]
        assetsByID = [:]
        loadedDirectoryVersion = directory.catalogVersion
        readerWindowStore.install(directory: directory)
        snapshotRevision += 1
        needsReaderRefresh = false
        isReaderLoading = false
        restoreReaderState()
        applyInitialFocusIfNeeded()
    }

    private func loadReaderQuestionUpdates(generation: Int) async {
        guard generation == readerQuestionUpdateGeneration,
              isReaderVisible,
              rootTabSelection.wrappedValue == .questionBank,
              !needsReaderRefresh,
              !pendingReaderQuestionIDs.isEmpty,
              let directory = readerDirectoryStore.directory else { return }
        let requestedIDs = pendingReaderQuestionIDs
        let compoundIDs = Set(directory.questions.compactMap { entry in
            requestedIDs.contains(entry.questionID) ? entry.sourceCompoundID : nil
        })
        guard !compoundIDs.isEmpty else {
            pendingReaderQuestionIDs.subtract(requestedIDs)
            return
        }
        let anchorID = currentVisibleQuestionID.flatMap { visibleID in
            directory.questions.first(where: { $0.questionID == visibleID })?.sourceCompoundID
        } ?? directory.orderedIDs.first ?? ""
        await readerWindowStore.loadWindow(
            container: modelContext.container,
            directory: directory,
            anchorID: anchorID,
            radius: presentationMode == .single
                ? QuestionBankReaderWindowBounds.singlePagePrefetchRadius
                : QuestionBankReaderWindowBounds.continuousPrefetchRadius,
            specificIDs: compoundIDs
        )
        guard generation == readerQuestionUpdateGeneration else { return }
        var answerLoadError: String?
        do {
            try await answerStateStore.load(Array(readerWindowStore.questionsByCompoundID.keys), from: modelContext.container)
        } catch {
            answerLoadError = "作答状态加载失败：\(error.localizedDescription)"
        }
        if let error = readerWindowStore.errorMessage { readerLoadError = error }
        else if let answerLoadError { readerLoadError = answerLoadError }
        pendingReaderQuestionIDs.subtract(requestedIDs)
        if reloadReaderWindowAfterQuestionUpdate {
            reloadReaderWindowAfterQuestionUpdate = false
            snapshotRevision &+= 1
        }
    }

    private func loadReaderWindow(aroundQuestionID requestedQuestionID: String? = nil) async {
        guard isReaderVisible, rootTabSelection.wrappedValue == .questionBank,
              let directory = readerDirectoryStore.directory,
              let visibleID = requestedQuestionID ?? currentVisibleQuestionID ?? readingItems.first?.id,
              let entry = directory.questions.first(where: { $0.questionID == visibleID }) else { return }
        await readerWindowStore.loadWindow(
            container: modelContext.container,
            directory: directory,
            anchorID: entry.sourceCompoundID,
            radius: presentationMode == .single
                ? QuestionBankReaderWindowBounds.singlePagePrefetchRadius
                : QuestionBankReaderWindowBounds.continuousPrefetchRadius
        )
        var answerLoadError: String?
        do {
            try await answerStateStore.load(Array(readerWindowStore.questionsByCompoundID.keys), from: modelContext.container)
        } catch {
            answerLoadError = "作答状态加载失败：\(error.localizedDescription)"
        }
        if let error = readerWindowStore.errorMessage { readerLoadError = error }
        else { readerLoadError = answerLoadError }
        materialsByID = Dictionary(
            readerWindowStore.materialsByCompoundID.values.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        assetsByID = Dictionary(
            readerWindowStore.assetsByCompoundID.values.map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private var doodleToolbarTarget: QuestionBankDoodleToolbarTarget? {
        QuestionBankDoodleToolbarTarget.resolve(
            visibleQuestionID: currentVisibleQuestionID,
            questions: readingItems.map(\.question),
            materialIDs: Set(materialsByID.keys)
        )
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if !readingItems.isEmpty {
                    readerContent(width: geometry.size.width, height: geometry.size.height)
                } else if let readerLoadError {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "题目加载失败",
                            systemImage: "exclamationmark.triangle",
                            description: Text(readerLoadError)
                        )
                        Button("重试") { requestReaderSnapshot() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if isReaderLoading || snapshotRevision == 0 {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在准备题目…")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("当前模块暂无题目", systemImage: "text.book.closed")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: "\(readerSnapshotGeneration)|\(isReaderVisible)") {
            await loadReaderSnapshot(generation: readerSnapshotGeneration)
        }
        .task(id: "legacy-answer-migration|\(paperID)|\(moduleID)") {
            await migrateLegacyAnswerStateIfNeeded()
        }
        .task(id: "\(readerQuestionUpdateGeneration)|\(isReaderVisible)") {
            await loadReaderQuestionUpdates(generation: readerQuestionUpdateGeneration)
        }
        .task(id: "\(currentVisibleQuestionID ?? "")|\(isReaderVisible)|\(snapshotRevision)|\(presentationMode.rawValue)") {
            await loadReaderWindow()
        }
        .overlay(alignment: .top) {
            if !readingItems.isEmpty, let readerLoadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text("题目刷新失败：\(readerLoadError)")
                        .font(AppTheme.auxiliaryFont)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("重试") { requestReaderSnapshot() }
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .zIndex(99)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsReaderOptions {
                readerOptionsOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsReaderOptions)
        .background(Color.white)
        .navigationTitle(presentationMode == .single ? "" : (module?.title ?? "真题阅读"))
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar {
            if presentationMode == .single {
                ToolbarItem(placement: .principal) {
                    Button {
                        guard let currentSingleItem, currentSingleItem.isLoaded, !doodleSession.isPresented else { return }
                        activeSheet = QuestionBankReaderSheet(content: .questionDetail(currentSingleItem.id))
                    } label: {
                        Text(singlePositionText)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(currentSingleItem.map {
                        "打开第\(displayNumber(for: $0))题详情，当前进度\(singlePositionText)"
                    } ?? "当前题进度")
                    .accessibilityHint("打开当前题目详情")
                    .accessibilityIdentifier("question-bank-single-position")
                    .disabled(currentSingleItem?.isLoaded != true || doodleSession.isPresented)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                questionBankToolbar
            }
            .documentToolbarBackground()
        }
        .sheet(item: $activeSheet, onDismiss: handleReaderSheetDismissal) { sheet in
            switch sheet.content {
            case .overview:
                QuestionBankQuestionOverviewSheet(
                    items: readingItems,
                    currentQuestionID: currentVisibleQuestionID,
                    container: modelContext.container,
                    assetLookup: assetRecord(for:),
                    onSelect: { handleOverviewSelection($0.overviewItem) }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .material(let materialID):
                materialPanel(for: materialID)
            case .questionDetail(let questionID):
                if let item = readingItem(for: questionID) {
                    questionDetailPanel(for: item)
                        .onAppear {
                            logQuestionBankDetailRoute(
                                event: "route-appear",
                                sheetID: sheet.id,
                                routeID: questionID,
                                item: item
                            )
                        }
                } else {
                    ContentUnavailableView("题目不存在", systemImage: "doc.text.magnifyingglass")
                        .onAppear {
                            logQuestionBankDetailRoute(
                                event: "route-missing",
                                sheetID: sheet.id,
                                routeID: questionID,
                                item: nil
                            )
                        }
                }
            }
        }
        .onAppear {
            isReaderRouteVisible = true
            activateReaderIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankRecordChangeSignal.notification)) { notification in
            guard QuestionBankRecordChangeSignal.affects(paperID, notification: notification) else { return }
            guard let changes = QuestionBankRecordChangeSignal.recordChanges(
                for: paperID,
                notification: notification
            ) else {
                requestReaderSnapshot()
                return
            }
            if changes.contains(where: { $0.kind == .structure }) {
                requestReaderSnapshot()
                return
            }
            if changes.contains(where: { $0.kind == .questionContent }) {
                requestReaderSnapshot()
                return
            }
            guard !readingItems.isEmpty else {
                requestReaderSnapshot()
                return
            }
            let visibleQuestionIDs = Set(readingItems.map(\.id))
            requestReaderQuestionUpdates(
                Set(changes.filter {
                    ($0.kind == .questionContent || $0.kind == .questionAnalysis || $0.kind == .questionLinks)
                        && visibleQuestionIDs.contains($0.recordID)
                }.map(\.recordID))
            )
        }
        .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
            if selectedTab == .questionBank {
                activateReaderIfNeeded()
            } else {
                if isReaderLoading { needsReaderRefresh = true }
                isReaderVisible = false
                readerWindowStore.cancel(clear: true)
                materialsByID = [:]
                assetsByID = [:]
            }
        }
        .onChange(of: snapshotRevision) { _, _ in applyInitialFocusIfNeeded() }
        .onChange(of: presentationMode) { _, mode in
            if mode != .continuous { continuousQuestionDoodleRecordID = nil }
        }
        .onChange(of: doodleSession.isPresented) { _, isPresented in
            if !isPresented { continuousQuestionDoodleRecordID = nil }
        }
        .onDisappear {
            isReaderRouteVisible = false
            if isReaderLoading || !pendingReaderQuestionIDs.isEmpty { needsReaderRefresh = true }
            isReaderVisible = false
            readerWindowStore.cancel(clear: true)
            materialsByID = [:]
            assetsByID = [:]
            readerDirectoryStore.cancel(clear: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankAnswerStateRepository.changeNotification)) { notification in
            guard notification.userInfo?[QuestionBankAnswerStateRepository.resetKey] as? Bool == true else { return }
            let currentIDs = Array(readerWindowStore.questionsByCompoundID.keys)
            Task {
                await Task.yield()
                do {
                    try await answerStateStore.load(currentIDs, from: modelContext.container)
                } catch {
                    readerLoadError = "作答状态重新加载失败：\(error.localizedDescription)"
                }
            }
        }
        .alert("答案更新", isPresented: Binding(
            get: { missingAnswerEditError != nil || missingAnswerEditConfirmation != nil },
            set: {
                if !$0 {
                    missingAnswerEditError = nil
                    missingAnswerEditConfirmation = nil
                }
            }
        )) {
            Button("好", role: .cancel) {
                missingAnswerEditError = nil
                missingAnswerEditConfirmation = nil
            }
        } message: {
            Text(missingAnswerEditError ?? missingAnswerEditConfirmation ?? "")
        }
    }

    private func readerContent(width: CGFloat, height: CGFloat) -> some View {
        let canOpenSplit = horizontalSizeClass == .regular && width >= 700
        let splitOrientation = QuestionBankSplitLayout.orientation(width: width, height: height)
        return Group {
            if let splitMaterialID, presentationMode == .continuous {
                splitReader(
                    materialID: splitMaterialID,
                    width: width,
                    height: height,
                    orientation: splitOrientation
                )
            } else if presentationMode == .single {
                singleQuestionReader(height: height)
            } else {
                continuousReader(canOpenSplit: canOpenSplit)
            }
        }
        .frame(width: width, height: height)
        .onChange(of: splitOrientation) { _, _ in
            guard presentationMode == .continuous, splitMaterialID != nil,
                  let questionID = currentVisibleQuestionID else { return }
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
        .task(id: "\(snapshotRevision)-\(canOpenSplit)-\(presentationMode.rawValue)") {
            guard canOpenSplit, presentationMode == .continuous,
                  !didApplyAutomaticDataAnalysisSplit, splitMaterialID == nil,
                  QuestionBankCoarseModule.classify(explicitModuleTitle: module?.title) == .dataAnalysis else { return }
            let focusedID = currentVisibleQuestionID ?? initialFocusQuestionID
            guard let item = focusedID.flatMap(readingItem(for:)) ?? readingItems.first,
                  !item.question.materialID.isEmpty,
                  materialsByID[item.question.materialID] != nil else { return }
            didApplyAutomaticDataAnalysisSplit = true
            currentVisibleQuestionID = item.id
            splitMaterialID = item.question.materialID
        }
        .overlay {
            QuestionBankDoodleAutosaveObserver(session: doodleSession, context: modelContext) {
                recordID, drawingData, error in
                guard error == nil else { return }
                cacheDoodleDrawing(drawingData, for: recordID)
            }
        }
        .overlay {
            if presentationMode == .continuous,
               doodleSession.isPresented,
               let recordID = continuousQuestionDoodleRecordID,
               doodleSession.targetRecordID == recordID {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: recordID,
                    minimumCanvasHeight: height
                )
            }
        }
        .onChange(of: scenePhase) { oldPhase, phase in
            switch phase {
            case .inactive:
                if let currentVisibleQuestionID { storedQuestionID = currentVisibleQuestionID }
                storedSplitMaterialID = splitMaterialID ?? ""
            case .background:
                if let currentVisibleQuestionID { storedQuestionID = currentVisibleQuestionID }
                storedSplitMaterialID = splitMaterialID ?? ""
                doodleSession.canvas.controller.invalidateDecodedDrawing()
            case .active:
                if oldPhase == .background {
                    invalidateDoodleCache()
                    doodleSession.canvas.controller.invalidateDecodedDrawing()
                    restoreReaderPosition()
                }
            @unknown default:
                break
            }
        }
    }

    private var questionBankToolbar: some View {
        HStack(spacing: 0) {
            if doodleSession.isPresented {
                if presentationMode == .single, doodleToolbarTarget != nil {
                    Color.clear
                        .frame(width: 44, height: 44)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Color.clear
                    .frame(width: 44, height: 44)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            } else {
                if presentationMode == .single { questionDoodleToolbarItems }
                questionOverviewButton
                readerOptionsMenu
            }
        }
        .frame(minHeight: 44)
        .id(doodleSession.isPresented ? "question-bank-toolbar-doodle" : "question-bank-toolbar-reader")
    }

    private var readerOptionsMenu: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsReaderOptions.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel("阅读设置")
        .accessibilityValue("浏览方式：\(presentationMode.title)，答题方式：\(readingMode.title)，选择后确认答案：\(requiresAnswerConfirmation ? "开启" : "关闭")")
        .accessibilityHint("打开设置，调整浏览方式、答题方式和答案确认")
        .accessibilityIdentifier("question-bank-reader-options")
        .disabled(doodleSession.isPresented)
    }

    private var readerOptionsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showsReaderOptions = false }
            QuestionBankReaderOptionsPopover(
                presentationMode: Binding(
                    get: { presentationMode },
                    set: { selectPresentationMode($0) }
                ),
                readingMode: Binding(
                    get: { readingMode },
                    set: { guard !doodleSession.isPresented else { return }; readingMode = $0 }
                ),
                requiresAnswerConfirmation: Binding(
                    get: { requiresAnswerConfirmation },
                    set: { setAnswerConfirmationEnabled($0) }
                ),
                currentQuestionTitle: currentVisibleQuestionID
                    .flatMap(readingItem(for:))
                    .map { "第\(displayNumber(for: $0))题" },
                onClearCurrentQuestion: {
                    guard let questionID = currentVisibleQuestionID,
                          let item = readingItem(for: questionID) else { return }
                    clearAnswer(for: item.record.compoundID)
                },
                onDismiss: { showsReaderOptions = false }
            )
            .padding(.top, 6)
            .padding(.trailing, 8)
        }
    }

    @ViewBuilder
    private var questionDoodleToolbarItems: some View {
        if let target = doodleToolbarTarget {
            currentQuestionDoodleButton(target)
        }
    }

    @ViewBuilder
    private func currentQuestionDoodleButton(_ target: QuestionBankDoodleToolbarTarget) -> some View {
        let button = Button {
            guard let item = readingItem(for: target.questionID) else { return }
            openQuestionDoodle(item)
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("标注当前题（第\(target.questionNumber)题）")
        .accessibilityHint(target.materialID == nil ? "打开当前题涂鸦" : "轻点标注当前题，长按可选择标注共用材料")
        .accessibilityIdentifier("question-bank-doodle-current-question")
        .disabled(doodleSession.isPresented)

        if let materialID = target.materialID {
            button
                .contextMenu {
                    Button {
                        openMaterialDoodle(materialID)
                    } label: {
                        Label("标注共用材料", systemImage: "pencil.and.scribble")
                    }
                }
                .accessibilityAction(named: Text("标注共用材料")) {
                    guard !doodleSession.isPresented else { return }
                    openMaterialDoodle(materialID)
                }
        } else {
            button
        }
    }

    private var questionOverviewButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            activeSheet = QuestionBankReaderSheet(content: .overview)
        } label: {
            Image(systemName: "square.grid.3x3")
                .font(.system(size: 14, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
                .foregroundStyle(AppTheme.accent.opacity(0.86))
        }
        .accessibilityLabel("题号总览")
        .disabled(readingItems.isEmpty || doodleSession.isPresented)
        .accessibilityIdentifier("question-bank-number-overview")
    }

    @ViewBuilder
    private func continuousReader(canOpenSplit: Bool) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(readingSteps) { step in
                                switch step.kind {
                                case .material(let materialID):
                                    if let material = materialsByID[materialID] {
                                        materialSection(material, canOpenSplit: canOpenSplit)
                                            .id(step.id)
                                    }
                                case .question(let questionID):
                                    if let item = readingItem(for: questionID) {
                                        questionSection(
                                            item,
                                            showsDoodleCanvas: false,
                                            showsDoodleButton: true,
                                            showsQuestionType: false
                                        )
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented)
                .coordinateSpace(name: "question-bank-continuous-scroll")
                .accessibilityIdentifier("question-bank-continuous-scroll")
                .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                .onChange(of: continuousScrollRequest) { _, request in
                    guard request != nil else { return }
                    consumeContinuousScrollRequest(using: proxy)
                }
                .onAppear { consumeContinuousScrollRequest(using: proxy) }
            }
        }
    }

    @ViewBuilder
    private func singleQuestionReader(height: CGFloat) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else if let item = currentSingleItem {
            QuestionBankInteractivePageDeck(
                currentID: item.id,
                previousID: QuestionBankReaderTransition.adjacentQuestionID(
                    currentID: item.id, orderedIDs: orderedQuestionIDs, direction: -1
                ),
                nextID: QuestionBankReaderTransition.adjacentQuestionID(
                    currentID: item.id, orderedIDs: orderedQuestionIDs, direction: 1
                ),
                isEnabled: !doodleSession.isPresented,
                onCommit: navigateSingleQuestion(to:)
            ) { pageID, isPageInactiveOrDragging in
                if let pageItem = readingItem(for: pageID) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !pageItem.question.materialID.isEmpty,
                               let material = materialsByID[pageItem.question.materialID] {
                                singleMaterialContent(material)
                            }
                            questionSection(
                                pageItem,
                                showsQuestionNumber: false,
                                showsDoodleCanvas: false,
                                showsQuestionType: false,
                                reportsVisibility: !isPageInactiveOrDragging
                            )
                        }
                        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .overlay {
                            LibraryDoodleContentLayer(
                                session: doodleSession,
                                targetRecordID: doodleRecordID(for: .question(pageItem.id)),
                                minimumCanvasHeight: height
                            )
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented || isPageInactiveOrDragging)
                    .scrollBounceBehavior(.basedOnSize)
                    .coordinateSpace(name: "question-bank-continuous-scroll")
                    .accessibilityIdentifier("question-bank-single-page-scroll")
                } else {
                    Color.clear
                }
            }
        } else {
            emptyModuleState
        }
    }

    private func singleMaterialContent(_ material: QuestionBankMaterial) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(material.type.isEmpty ? "共用材料" : "共用材料 · \(material.type)")
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(AppTheme.accent)
            if !material.text.isEmpty {
                Text(verbatim: material.text)
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !material.imageAssetID.isEmpty,
               let asset = assetRecord(for: material.imageAssetID) {
                QuestionBankLocalImage(asset: asset, sizing: .material)
            }
            QuestionBankProvenanceDisclosure(
                title: "材料来源", entries: material.provenance ?? [],
                sourcePapers: sourcePapers
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.35)).frame(height: 1)
        }
    }

    @ViewBuilder
    private func splitReader(
        materialID: String,
        width: CGFloat,
        height: CGFloat,
        orientation: QuestionBankSplitOrientation
    ) -> some View {
        if let material = materialsByID[materialID] {
            let groupedQuestions = readingItems.filter { $0.question.materialID == materialID }
            Group {
                if orientation == .landscape {
                    HStack(spacing: 0) {
                        materialPane(material)
                            .frame(width: QuestionBankSplitLayout.materialWidth(totalWidth: width))
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.65))
                            .frame(width: 1)
                        questionPane(groupedQuestions)
                            .frame(minWidth: QuestionBankSplitLayout.minimumQuestionPaneWidth)
                    }
                } else {
                    VStack(spacing: 0) {
                        materialPane(material)
                            .frame(height: QuestionBankSplitLayout.materialHeight(totalHeight: height))
                        Rectangle()
                            .fill(Color(uiColor: .separator).opacity(0.65))
                            .frame(height: 1)
                        questionPane(groupedQuestions)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white)
        } else {
            emptyModuleState
        }
    }

    private func materialPane(_ material: QuestionBankMaterial) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("共用材料").font(AppTheme.sectionTitleFont)
                Spacer(minLength: 4)
                Button(action: closeSplitReader) {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("关闭分屏")
                .accessibilityIdentifier("question-bank-close-material-split")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
            ScrollView {
                materialContent(material)
                    .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(Color.white)
            .scrollDisabled(doodleSession.isPresented)
            .accessibilityIdentifier("question-bank-material-panel-scroll")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-bank-split-material-pane-\(material.id)")
    }

    private func questionPane(_ groupedQuestions: [QuestionBankReadingItem]) -> some View {
        Group {
            if presentationMode == .single,
               let item = currentVisibleQuestionID.flatMap({ readingItem(for: $0) }) ?? groupedQuestions.first {
                QuestionBankInteractivePageDeck(
                    currentID: item.id,
                    previousID: QuestionBankReaderTransition.adjacentQuestionID(
                        currentID: item.id, orderedIDs: orderedQuestionIDs, direction: -1
                    ),
                    nextID: QuestionBankReaderTransition.adjacentQuestionID(
                        currentID: item.id, orderedIDs: orderedQuestionIDs, direction: 1
                    ),
                    isEnabled: !doodleSession.isPresented,
                    onCommit: navigateSingleQuestion(to:)
                ) { pageID, isPageInactiveOrDragging in
                    if let pageItem = readingItem(for: pageID) {
                        ScrollView {
                            questionSection(
                                pageItem,
                                showsQuestionNumber: false,
                                showsDoodleCanvas: false,
                                showsQuestionType: false,
                                reportsVisibility: !isPageInactiveOrDragging
                            )
                                .padding(.horizontal, 18)
                                .padding(.vertical, 10)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.white)
                        .scrollDisabled(doodleSession.isPresented || isPageInactiveOrDragging)
                        .scrollBounceBehavior(.basedOnSize)
                        .coordinateSpace(name: "question-bank-continuous-scroll")
                    } else {
                        Color.clear
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(groupedQuestions) { item in
                                questionSection(
                                    readingItem(for: item.id) ?? item,
                                    showsDoodleCanvas: false,
                                    showsDoodleButton: true,
                                    showsQuestionType: false
                                )
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented)
                    .coordinateSpace(name: "question-bank-continuous-scroll")
                    .accessibilityIdentifier("question-bank-continuous-scroll")
                    .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                    .onChange(of: splitScrollRequest) { _, request in
                        guard let request else { return }
                        let target = groupedQuestions.first(where: { $0.id == request.questionID })?.id
                            ?? groupedQuestions.first?.id
                        guard let target else { return }
                        withAnimation(.easeInOut(duration: 0.22)) {
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                    .onAppear {
                        let preferred = currentVisibleQuestionID
                        let target = groupedQuestions.first(where: { $0.id == preferred })?.id
                            ?? groupedQuestions.first(where: { $0.id == splitScrollRequest?.questionID })?.id
                            ?? groupedQuestions.first?.id
                        guard let target else { return }
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(target, anchor: .top)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("question-bank-split-question-pane")
    }

    private func materialContent(_ material: QuestionBankMaterial, showsHeading: Bool = false) -> some View {
        QuestionBankMaterialBody(
            material: material,
            imageAsset: assetRecord(for: material.imageAssetID),
            showsHeading: showsHeading
        )
        .overlay {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: doodleRecordID(for: .material(material.id)),
                minimumCanvasHeight: 0
            )
        }
    }

    private var emptyModuleState: some View {
        Group {
            if module == nil {
                NativeStatusCard(
                    title: "模块不存在",
                    detail: "此模块可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            } else {
                NativeStatusCard(
                    title: "本次样本未收录题目",
                    detail: "该模块已保留在试卷结构中，当前导入样本没有可阅读的题目。",
                    systemImage: "doc.text.magnifyingglass",
                    color: AppTheme.accent
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func materialSection(_ material: QuestionBankMaterial, canOpenSplit: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Text("共用材料")
                    .font(AppTheme.sectionTitleFont)
                if !material.type.isEmpty {
                    Text(material.type)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    openMaterial(material.id, canOpenSplit: canOpenSplit)
                } label: {
                    Image(systemName: "rectangle.split.2x1")
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(canOpenSplit ? "分屏看材料" : "查看材料")
                .accessibilityIdentifier("question-bank-split-material-\(material.id)")
            }
            materialContent(material)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func questionSection(
        _ item: QuestionBankReadingItem,
        showsQuestionNumber: Bool = true,
        showsDoodleCanvas: Bool = true,
        showsDoodleButton: Bool = false,
        showsQuestionType: Bool = true,
        reportsVisibility: Bool = true
    ) -> some View {
        let answerStateID = item.record.compoundID
        let selectedOptionID = selectedAnswerOption(for: answerStateID)
        let hasAnswer = !item.question.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showsGraphLayout = QuestionBankCoarseModule.classify(
            explicitModuleTitle: item.moduleTitle
        ) == .reasoning
        let revealsAnswer = readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: isAnswerRevealed(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        let heading = showsQuestionType ? QuestionBankQuestionHeading.displayLabel(
            type: item.question.type,
            subject: item.question.subject,
            moduleTitle: item.moduleTitle
        ) : nil
        return VStack(alignment: .leading, spacing: 0) {
            if showsQuestionNumber || heading != nil {
                HStack(spacing: 8) {
                    if showsQuestionNumber { questionNumberButton(for: item) }
                    if let heading {
                        Text(heading)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if showsDoodleButton {
                        Button { openQuestionDoodle(item) } label: {
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 16, weight: .regular))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("标注第\(displayNumber(for: item))题")
                        .accessibilityHint("仅标注这道题")
                        .accessibilityIdentifier("question-bank-doodle-question-\(item.id)")
                        .disabled(doodleSession.isPresented)
                    }
                }
                .padding(.bottom, 7)
            }

            VStack(alignment: .leading, spacing: 0) {
                QuestionBankQuestionAnnotationBadges(question: item.question)
                if !item.question.stem.isEmpty {
                    Text(verbatim: item.question.stem)
                        .font(QuestionBankTypography.contentFont)
                        .lineSpacing(QuestionBankTypography.contentLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, 10)
                        .accessibilityIdentifier("question-bank-question-stem-\(item.id)")
                }
                if !item.question.stemImageAssetID.isEmpty,
                   let asset = assetRecord(for: item.question.stemImageAssetID) {
                    QuestionBankLocalImage(asset: asset, sizing: showsGraphLayout ? .graph : .stem)
                        .padding(.bottom, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selectedOptionID,
                    revealsAnswer: revealsAnswer,
                    isSelectionLocked: readingMode == .practice && selectedOptionID != nil,
                    isInteractionBlocked: doodleSession.isPresented || !answerStateStore.isLoaded(answerStateID),
                    showsGraphLayout: showsGraphLayout,
                    onSelect: { selectOption(option.id, for: item) },
                    assetLookup: assetRecord(for:)
                )
            }

            if readingMode == .reading, hasAnswer {
                HStack(spacing: 7) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(QuestionBankAnswerFeedbackPalette.correct)
                    Text("正确答案")
                        .foregroundStyle(.secondary)
                    Text(item.question.answer.isEmpty ? "未提供" : item.question.answer)
                        .fontWeight(.semibold)
                        .foregroundStyle(QuestionBankAnswerFeedbackPalette.correct)
                }
                .font(QuestionBankTypography.contentFont)
                .padding(.top, 12)
            } else if readingMode == .practice {
                if revealsAnswer, let selectedOptionID, hasAnswer {
                    HStack(spacing: 8) {
                        Text("你的选择：\(selectedOptionID)")
                            .foregroundStyle(selectedOptionID == item.question.answer
                                ? QuestionBankAnswerFeedbackPalette.correct
                                : QuestionBankAnswerFeedbackPalette.incorrect)
                        Spacer(minLength: 8)
                        Text("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)")
                            .fontWeight(.semibold)
                            .foregroundStyle(QuestionBankAnswerFeedbackPalette.correct)
                    }
                    .font(AppTheme.auxiliaryFont)
                    .padding(.top, 12)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("question-bank-answer-feedback-\(item.id)")
                    QuestionBankAnswerFollowUpAction(analysis: questionAnalysisContext(for: item))
                        .padding(.top, 7)
                } else if requiresAnswerConfirmation {
                    HStack {
                        Spacer(minLength: 0)
                        Button {
                            confirmAnswer(for: answerStateID)
                        } label: {
                            Text("确认答案")
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                                .frame(minWidth: 96, minHeight: 40)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedOptionID == nil || doodleSession.isPresented)
                        .accessibilityLabel("确认答案并查看正确选项")
                        .accessibilityIdentifier("question-bank-confirm-answer-\(item.id)")
                    }
                    .padding(.top, 12)
                    if selectedOptionID == nil {
                        QuestionBankAnswerFollowUpAction(
                            analysis: questionAnalysisContext(for: item),
                            categoryOverride: .cannotSolve
                        )
                        .padding(.top, 7)
                    }
                } else if selectedOptionID == nil {
                    QuestionBankAnswerFollowUpAction(
                        analysis: questionAnalysisContext(for: item),
                        categoryOverride: .cannotSolve
                    )
                    .padding(.top, 7)
                }
            }
            if hasAnswer && (readingMode == .reading || revealsAnswer) {
                QuestionBankReferenceAccuracyControl(
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    accuracy: item.question.accuracy
                )
                    .padding(.top, 7)
                    .transition(.opacity)
            }
            if !hasAnswer {
                QuestionBankMissingAnswerMenu(questionID: item.id, options: item.question.options) { answer in
                    setMissingAnswer(answer, for: item)
                }
                .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .background {
            if reportsVisibility {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .named("question-bank-continuous-scroll"))
                    Color.clear.preference(
                        key: QuestionBankReaderViewportPreference.self,
                        value: [item.id: QuestionBankReaderViewportFrame(top: frame.minY, bottom: frame.maxY)]
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
        .overlay {
            if showsDoodleCanvas {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: doodleRecordID(for: .question(item.id)),
                    minimumCanvasHeight: 0
                )
            }
        }
        .frame(minHeight: item.isLoaded ? 0 : 108)
        .overlay {
            if !item.isLoaded {
                ProgressView("正在加载题目…")
                    .font(AppTheme.auxiliaryFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.96))
                    .allowsHitTesting(false)
            }
        }
        .disabled(!item.isLoaded)
        .id(item.id)
    }

    private func questionNumberButton(for item: QuestionBankReadingItem) -> some View {
        let displayNumber = displayNumber(for: item)
        return Button {
            guard item.isLoaded, !doodleSession.isPresented else { return }
            activeSheet = QuestionBankReaderSheet(content: .questionDetail(item.id))
        } label: {
            Text("\(displayNumber).")
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开第\(displayNumber)题详情")
        .accessibilityHint("查看题干、选项和解析")
        .accessibilityIdentifier("question-bank-question-detail-\(item.id)")
        .disabled(!item.isLoaded || doodleSession.isPresented)
    }

    private func displayNumber(for item: QuestionBankReadingItem) -> Int {
        QuestionBankDisplayNumber.resolve(
            originalNumber: item.question.number,
            localOrdinal: item.localOrdinal,
            usesLocalOrdinal: true
        )
    }

    private func questionDetailContent(_ item: QuestionBankReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if !item.question.materialID.isEmpty,
               let material = materialsByID[item.question.materialID] {
                materialContent(material, showsHeading: true)
                    .padding(.bottom, 12)
                QuestionBankProvenanceDisclosure(
                    title: "材料来源", entries: material.provenance ?? [],
                    sourcePapers: sourcePapers
                )
                    .padding(.bottom, 12)
            }
            questionSection(item, showsQuestionNumber: false)
            QuestionBankProvenanceDisclosure(
                title: "题目来源", entries: item.question.provenance ?? [],
                sourcePapers: sourcePapers
            )
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func questionDetailPanel(for item: QuestionBankReadingItem) -> some View {
        let record = persistedQuestionRecord(for: item) ?? item.record
        let detailContext = questionAnalysisContext(for: item, record: record)
        if detailContext.typeMapping.subject == "申论" {
            QuestionBankQuestionDetailPanel(
                question: item.question,
                title: "第\(item.question.number)题详情",
                isDoodlePresented: doodleSession.isPresented,
                onDone: { activeSheet = nil },
                onClearAnswer: { clearAnswer(for: item.record.compoundID) },
                onSave: { stem, optionTexts, annotations in
                    try QuestionBankRepository.updateQuestionText(
                        paperID: paperID,
                        questionID: item.question.id,
                        stem: stem,
                        optionTexts: optionTexts,
                        annotations: annotations,
                        moduleTitle: item.moduleTitle,
                        context: modelContext
                    )
                }
            ) {
                ScrollView {
                    questionDetailContent(item)
                }
                .coordinateSpace(name: "question-bank-continuous-scroll")
                .scrollContentBackground(.hidden)
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented)
            }
        } else {
            NavigationStack {
                LibraryRecordDetailView(
                    questionBankContext: detailContext,
                    onEdit: {},
                    onClearAnswer: { clearAnswer(for: item.record.compoundID) },
                    onDone: { activeSheet = nil }
                )
            }
            .presentationDetents([.large])
        }
    }

    private func questionAnalysisContext(
        for item: QuestionBankReadingItem,
        record: QuestionBankRecord? = nil
    ) -> QuestionBankQuestionAnalysisContext {
        let answerStateID = item.record.compoundID
        let selectedOptionID = selectedAnswerOption(for: answerStateID)
        let answerRevealed = readingMode == .reading || readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: isAnswerRevealed(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        return QuestionBankQuestionAnalysisContext(
            record: record ?? item.record,
            question: item.question,
            moduleTitle: item.moduleTitle,
            material: materialsByID[item.question.materialID],
            sourcePapers: sourcePapers,
            assetsByID: assetsByID,
            selectedOptionID: selectedOptionID,
            isAnswerRevealed: answerRevealed
        )
    }

    private func persistedQuestionRecord(for item: QuestionBankReadingItem) -> QuestionBankRecord? {
        let compoundID = item.record.compoundID
        var descriptor = FetchDescriptor<QuestionBankRecord>(
            predicate: #Predicate { $0.compoundID == compoundID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func openMaterial(_ materialID: String, canOpenSplit: Bool) {
        guard !doodleSession.isPresented else { return }
        guard canOpenSplit else {
            activeSheet = QuestionBankReaderSheet(content: .material(materialID))
            return
        }
        continuousAnchorQuestionID = currentVisibleQuestionID ?? continuousAnchorQuestionID
        splitMaterialID = materialID
        storedSplitMaterialID = materialID
        let preferredQuestion = readingItems.first {
            $0.id == currentVisibleQuestionID && $0.question.materialID == materialID
        }
        let target = preferredQuestion?.id ?? readingItems.first { $0.question.materialID == materialID }?.id
        if let target {
            currentVisibleQuestionID = target
            splitScrollRequest = QuestionBankScrollRequest(questionID: target, token: UUID())
        }
    }

    private func closeSplitReader() {
        guard !doodleSession.isPresented else { return }
        let returnTarget = currentVisibleQuestionID ?? continuousAnchorQuestionID
        splitMaterialID = nil
        storedSplitMaterialID = ""
        guard presentationMode == .continuous, let returnTarget else { return }
        continuousScrollRequest = QuestionBankScrollRequest(questionID: returnTarget, token: UUID())
    }

    private func materialPanel(for materialID: String) -> some View {
        Group {
            if let material = materialsByID[materialID] {
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            materialContent(material)
                            QuestionBankProvenanceDisclosure(
                                title: "材料来源", entries: material.provenance ?? [],
                                sourcePapers: sourcePapers
                            )
                        }
                        .padding(20)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented)
                    .accessibilityIdentifier("question-bank-material-panel-scroll")
                    .navigationTitle("共用材料")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { activeSheet = nil }
                        }
                    }
                    .task(id: "\(materialID)|\(snapshotRevision)") {
                        guard let questionID = readingItems.first(where: {
                            $0.question.materialID == materialID
                        })?.id else { return }
                        await loadReaderWindow(aroundQuestionID: questionID)
                    }
                }
            } else {
                NativeStatusCard(
                    title: "材料不存在",
                    detail: "该材料可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            }
        }
    }

    private func handleOverviewSelection(_ item: QuestionBankOverviewItem) {
        guard !doodleSession.isPresented else { return }
        pendingOverviewQuestionID = item.id
        continuousAnchorQuestionID = item.id
        let position = QuestionBankReaderTransition.selectingOverviewQuestion(
            item.id,
            materialID: item.materialID.isEmpty ? nil : item.materialID,
            availableMaterialIDs: directoryMaterialIDs,
            from: readerPosition
        )
        applyReaderPosition(position)
    }

    private func handleReaderSheetDismissal() {
        guard let questionID = pendingOverviewQuestionID else { return }
        pendingOverviewQuestionID = nil
        let request = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        if splitMaterialID != nil {
            splitScrollRequest = request
        } else if presentationMode == .continuous {
            continuousScrollRequest = request
        }
    }

    private func applyReaderPosition(_ position: QuestionBankReaderPosition) {
        presentationMode = position.presentationMode
        currentVisibleQuestionID = position.currentQuestionID
        splitMaterialID = position.splitMaterialID
    }

    private func selectPresentationMode(_ mode: QuestionBankPresentationMode) {
        guard !doodleSession.isPresented else { return }
        guard mode != presentationMode else {
            showsReaderOptions = false
            return
        }
        var source = readerPosition
        if source.currentQuestionID == nil {
            source.currentQuestionID = currentSingleItem?.id ?? initialFocusQuestionID
        }
        let position = QuestionBankReaderTransition.switchingPresentation(to: mode, from: source)
        applyReaderPosition(position)
        guard let questionID = position.currentQuestionID else { return }
        continuousAnchorQuestionID = questionID
        if position.splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if mode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
        showsReaderOptions = false
    }

    private func migrateLegacyAnswerStateIfNeeded() async {
        let selectedSnapshot = storedSelectedOptionsJSON
        let revealedSnapshot = storedRevealedAnswersJSON
        do {
            try await answerStateStore.migrateGlobalIfNeeded(in: modelContext.container)
            try await answerStateStore.migrateSceneStorageIfNeeded(
                sourceKey: "\(legacySelectedOptionsStorageKey)|\(legacyRevealedAnswersStorageKey)",
                selectedOptionsJSON: selectedSnapshot,
                revealedAnswersJSON: revealedSnapshot,
                paperID: paperID,
                in: modelContext.container
            )
            if storedSelectedOptionsJSON == selectedSnapshot { storedSelectedOptionsJSON = "{}" }
            if storedRevealedAnswersJSON == revealedSnapshot { storedRevealedAnswersJSON = "[]" }
        } catch {
            readerLoadError = "旧作答数据迁移失败，原始备份已保留：\(error.localizedDescription)"
        }
    }

    private func clearAnswer(for questionID: String) {
        Task {
            do {
                try await answerStateStore.clear([questionID], in: modelContext.container)
            } catch {
                readerLoadError = "清除作答状态失败：\(error.localizedDescription)"
            }
        }
    }

    private func navigateSingleQuestion(to targetID: String) {
        guard presentationMode == .single, !doodleSession.isPresented else { return }
        guard let target = readingItem(for: targetID) else { return }

        let hadSplitMaterial = splitMaterialID != nil
        let position = QuestionBankReaderTransition.movingToQuestion(
            targetID,
            materialID: target.question.materialID.isEmpty ? nil : target.question.materialID,
            availableMaterialIDs: directoryMaterialIDs,
            from: readerPosition
        )
        applyReaderPosition(position)
        continuousAnchorQuestionID = targetID

        if hadSplitMaterial, position.splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: targetID, token: UUID())
        }
    }

    private func selectOption(_ optionID: String, for item: QuestionBankReadingItem) {
        let questionID = item.record.compoundID
        guard !doodleSession.isPresented,
              readingMode == .practice,
              answerStateStore.isLoaded(questionID),
              !isAnswerRevealed(questionID) else { return }
        guard selectedAnswerOption(for: questionID) == nil else { return }
        Task {
            do {
                try await answerStateStore.setSelection(
                    optionID,
                    for: questionID,
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    revealed: !requiresAnswerConfirmation,
                    in: modelContext.container
                )
            } catch {
                readerLoadError = "保存作答状态失败：\(error.localizedDescription)"
            }
        }
    }

    private func setAnswerConfirmationEnabled(_ enabled: Bool) {
        guard !doodleSession.isPresented else { return }
        requiresAnswerConfirmation = enabled
        if !enabled {
            Task {
                do {
                    try await answerStateStore.markAllSelectedRevealed(in: modelContext.container)
                } catch {
                    readerLoadError = "更新答案确认状态失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func confirmAnswer(for questionID: String) {
        guard !doodleSession.isPresented,
              selectedAnswerOption(for: questionID) != nil,
              let item = readingItems.first(where: { $0.record.compoundID == questionID }) else { return }
        Task {
            do {
                try await answerStateStore.setRevealed(
                    true,
                    for: questionID,
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    in: modelContext.container
                )
            } catch {
                readerLoadError = "确认答案失败：\(error.localizedDescription)"
            }
        }
    }

    private func setMissingAnswer(_ answer: String, for item: QuestionBankReadingItem) {
        do {
            try QuestionBankRepository.setMissingAnswer(
                paperID: paperID,
                questionID: item.question.id,
                answer: answer,
                context: modelContext
            )
            missingAnswerEditConfirmation = "答案已补录为 \(answer)。"
        } catch {
            missingAnswerEditError = error.localizedDescription
            missingAnswerEditConfirmation = nil
        }
    }

    private func updateVisibleQuestion(_ frames: [String: QuestionBankReaderViewportFrame]) {
        guard presentationMode == .continuous else { return }
        guard let visible = frames
            .filter({ $0.value.bottom > 1 })
            .min(by: { $0.value.top < $1.value.top })?.key else { return }
        guard currentVisibleQuestionID != visible else { return }
        currentVisibleQuestionID = visible
        if splitMaterialID == nil { continuousAnchorQuestionID = visible }
    }

    private func applyInitialFocusIfNeeded() {
        guard !didApplyInitialFocus else { return }
        let restoredID = readingItems.first(where: { $0.id == currentVisibleQuestionID })?.id
        guard let questionID = initialFocusQuestionID ?? restoredID else { return }
        didApplyInitialFocus = true
        currentVisibleQuestionID = questionID
        continuousAnchorQuestionID = questionID
        if let item = readingItem(for: questionID), splitMaterialID != nil {
            reconcileSplitMaterial(for: item)
        }
        if splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if presentationMode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
    }

    private func restoreReaderState() {
        applyInitialFocusIfNeeded()
        if splitMaterialID != nil,
           let questionID = currentVisibleQuestionID,
           let item = readingItem(for: questionID) {
            reconcileSplitMaterial(for: item)
            if self.splitMaterialID != nil {
                splitScrollRequest = QuestionBankScrollRequest(questionID: item.id, token: UUID())
            } else if presentationMode == .continuous {
                continuousScrollRequest = QuestionBankScrollRequest(questionID: item.id, token: UUID())
            }
        }
    }

    private func restoreReaderPosition() {
        guard let item = readingItems.first(where: { $0.id == currentVisibleQuestionID }) else { return }
        let questionID = item.id
        currentVisibleQuestionID = questionID
        if splitMaterialID != nil {
            reconcileSplitMaterial(for: item)
        }
        if splitMaterialID != nil {
            splitScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        } else if presentationMode == .continuous {
            continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        }
    }

    private func reconcileSplitMaterial(for item: QuestionBankReadingItem) {
        guard splitMaterialID != nil else { return }
        let materialID = item.question.materialID
        splitMaterialID = !materialID.isEmpty && materialID == splitMaterialID ? materialID : nil
    }

    private func doodleRecordID(for scope: QuestionBankDoodleScope) -> String {
        QuestionBankDoodleRepository.recordID(paperID: paperID, scope: scope)
    }

    private func openMaterialDoodle(_ materialID: String) {
        continuousQuestionDoodleRecordID = nil
        presentDoodle(for: .material(materialID))
    }

    private func openQuestionDoodle(_ item: QuestionBankReadingItem) {
        guard !doodleSession.isPresented else { return }
        continuousQuestionDoodleRecordID = presentationMode == .continuous
            ? doodleRecordID(for: .question(item.id))
            : nil
        presentDoodle(for: .question(item.id))
    }

    private func presentDoodle(for scope: QuestionBankDoodleScope) {
        let recordID = doodleRecordID(for: scope)
        let readStart = ProcessInfo.processInfo.systemUptime
        let loadState = QuestionBankDoodleMemoryCache.shared.state(for: recordID)
        let cached = loadState.drawingData
        if loadState != .unknown { LibraryPerformanceLog.mark("doodle.read.cache-hit", since: readStart) }
        doodleSession.present(
            targetRecordID: recordID,
            drawingData: cached ?? "",
            legacyPreviewDataURL: "",
            isLoadingDrawing: cached == nil,
            source: "question-bank-module",
            onSave: { drawingData, _, generation, revision in
                QuestionBankDoodleRepository.enqueueSave(
                    recordID: recordID,
                    drawingData: drawingData,
                    container: modelContext.container,
                    presentationGeneration: generation,
                    drawingRevision: revision,
                    debounceMilliseconds: 0
                ) { error in
                    guard doodleSession.presentationGeneration == generation,
                          doodleSession.targetRecordID == recordID else { return }
                    doodleSession.saveError = error
                    if error == nil { cacheDoodleDrawing(drawingData, for: recordID) }
                }
                return nil
            }
        )
        LibraryPerformanceLog.mark("doodle.tap-to-feedback", since: readStart)
        guard loadState == .unknown else { return }
        let container = modelContext.container
        doodleSession.beginDrawingLoad(recordID: recordID, startedAt: readStart) {
            try await QuestionBankDoodleRepository.drawingData(
                recordID: recordID,
                container: container
            )
        } onLoaded: { drawingData in
            cacheDoodleDrawing(drawingData, for: recordID)
        }
    }

    private func cachedDoodleDrawing(for recordID: String) -> String? {
        QuestionBankDoodleMemoryCache.shared.drawingData(for: recordID)
    }

    private func cacheDoodleDrawing(_ drawingData: String, for recordID: String) {
        QuestionBankDoodleMemoryCache.shared.store(drawingData, for: recordID)
    }

    private func invalidateDoodleCache() {
        QuestionBankDoodleMemoryCache.shared.invalidate()
    }

    private func consumeContinuousScrollRequest(using proxy: ScrollViewProxy) {
        guard let request = continuousScrollRequest else { return }
        continuousScrollRequest = nil
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(request.questionID, anchor: .top)
            }
        }
    }

    private func readingItem(for id: String) -> QuestionBankReadingItem? {
        guard let directoryItem = readingItems.first(where: { $0.id == id }) else { return nil }
        guard let loaded = readerWindowStore.question(for: directoryItem.record.compoundID) else {
            return directoryItem
        }
        return QuestionBankReadingItem(
            record: directoryItem.record,
            question: loaded.question,
            moduleTitle: directoryItem.moduleTitle,
            moduleSequence: directoryItem.moduleSequence,
            isLoaded: true,
            localOrdinal: directoryItem.localOrdinal
        )
    }

    private func logQuestionBankDetailRoute(
        event: String,
        sheetID: UUID,
        routeID: String,
        item: QuestionBankReadingItem?
    ) {
        #if DEBUG
        guard QuestionBankReaderUITestFixture.isEnabled else { return }
        let record = item?.record
        let question = item?.question
        NSLog("%@", "[QBankDetailRoute] event=\(event) sheet=\(sheetID.uuidString) route=\(routeID) item=\(item?.id ?? "missing") record=\(record?.compoundID ?? "missing") revision=\(record.map { String($0.contentRevision) } ?? "missing") stemChars=\(question.map { String($0.stem.count) } ?? "missing") noteChars=\(question.map { String(($0.note ?? "").count) } ?? "missing")")
        #endif
    }

    private func logQuestionBankSnapshotRefresh() {
        #if DEBUG
        guard QuestionBankReaderUITestFixture.isEnabled else { return }
        let activeRoute: String
        if let activeSheet {
            switch activeSheet.content {
            case .questionDetail(let questionID): activeRoute = "detail:\(questionID):\(activeSheet.id.uuidString)"
            case .overview: activeRoute = "overview:\(activeSheet.id.uuidString)"
            case .material(let materialID): activeRoute = "material:\(materialID):\(activeSheet.id.uuidString)"
            }
        } else {
            activeRoute = "none"
        }
        let activeItem = {
            if let content = activeSheet?.content,
               case .questionDetail(let questionID) = content {
                return readingItem(for: questionID)
            }
            return nil
        }()
        NSLog("%@", "[QBankDetailRoute] event=reader-snapshot-refresh active=\(activeRoute) item=\(activeItem?.id ?? "none") revision=\(activeItem.map { String($0.record.contentRevision) } ?? "none") stemChars=\(activeItem.map { String($0.question.stem.count) } ?? "none") noteChars=\(activeItem.map { String(($0.question.note ?? "").count) } ?? "none")")
        #endif
    }

    private func assetRecord(for id: String) -> QuestionBankAssetReference? {
        guard !id.isEmpty else { return nil }
        return assetsByID[id]
    }
}

private struct QuestionBankCrossPaperStep: Identifiable {
    let id: String
    let materialID: String?
    let material: QuestionBankMaterial?
    let question: QuestionBankHomeQuestion?
}

private struct QuestionBankCrossPaperGroup: Identifiable {
    let paperID: String
    let title: String
    let steps: [QuestionBankCrossPaperStep]
    let questions: [QuestionBankHomeQuestion]
    let materialsByID: [String: QuestionBankMaterial]
    let sourcePapers: [QuestionBankSourcePaper]

    var id: String { paperID }
}

private struct QuestionBankCrossPaperDetailRoute: Identifiable {
    let questionID: String
    var id: String { questionID }
}

struct QuestionBankCrossPaperReaderView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootTabSelection) private var rootTabSelection
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @StateObject private var readerDirectoryStore = QuestionBankReaderDirectoryStore()
    @StateObject private var readerWindowStore = QuestionBankReaderWindowStore()
    @StateObject private var answerStateStore = QuestionBankAnswerStateStore.shared

    let filter: QuestionBankHomeFilter
    let paperID: String?
    let scopedPaperIDs: [String]?

    @AppStorage(QuestionBankReaderPreferences.presentationModeKey)
    private var storedPresentationMode = QuestionBankPresentationMode.continuous.rawValue
    @State private var readingMode: QuestionBankReadingMode = .practice
    @State private var currentQuestionID: String?
    @State private var activeQuestionDetail: QuestionBankCrossPaperDetailRoute?
    @State private var groups: [QuestionBankCrossPaperGroup] = []
    @State private var orderedItems: [QuestionBankHomeQuestion] = []
    @State private var orderedItemIDs: [String] = []
    @State private var itemsByID: [String: QuestionBankHomeQuestion] = [:]
    @State private var groupsByPaperID: [String: QuestionBankCrossPaperGroup] = [:]
    @State private var localOrdinalByID: [String: Int] = [:]
    @State private var orderedOrdinalByID: [String: Int] = [:]
    @State private var overviewGroups: [QuestionBankOverviewGroup] = []
    @State private var isCrossPaperRouteVisible = false
    @State private var isCrossPaperVisible = false
    @State private var needsIndexReload = true
    @State private var crossPaperLoadGeneration = 0
    @State private var crossWindowLoadGeneration = 0
    @State private var crossQuestionUpdateGeneration = 0
    @State private var pendingCrossQuestionIDs = Set<String>()
    @State private var reloadCrossWindowAfterQuestionUpdate = false
    @State private var readerWindowError: String?
    @State private var showsReaderOptions = false
    @State private var showsOverview = false
    @State private var overviewAnswerStatesByID: [String: QuestionBankAnswerStateValue] = [:]
    @State private var continuousQuestionDoodleRecordID: String?
    @State private var missingAnswerEditError: String?
    @State private var missingAnswerEditConfirmation: String?
    @SceneStorage private var selectedOptionsJSON: String
    @SceneStorage private var revealedAnswersJSON: String
    private let legacyAnswerStorageKey: String
    @AppStorage(QuestionBankReaderPreferences.confirmAnswerAfterSelectionKey)
    private var requiresAnswerConfirmation = false

    init(filter: QuestionBankHomeFilter, paperID: String? = nil, paperIDs: [String]? = nil) {
        self.filter = filter
        self.paperID = paperID
        scopedPaperIDs = paperID.map { [$0] } ?? paperIDs.map { Array(Set($0)).sorted() }
        let scope = [
            filter.module?.rawValue ?? "", filter.questionType, filter.year, filter.examType,
            filter.province, filter.search, filter.questionNumber,
            String(filter.difficultOnly), String(filter.needsReviewOnly),
            filter.knowledgePoint, filter.weaknessTag, paperID ?? "all"
        ].joined(separator: "|")
        let key = Data(scope.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        let selectedKey = "question-bank.scope.selected-options.\(key)"
        let revealedKey = "question-bank.scope.revealed-answers.\(key)"
        _selectedOptionsJSON = SceneStorage(wrappedValue: "{}", selectedKey)
        _revealedAnswersJSON = SceneStorage(wrappedValue: "[]", revealedKey)
        legacyAnswerStorageKey = "\(selectedKey)|\(revealedKey)"
    }

    private var directory: QuestionBankReaderDirectorySnapshot? { readerDirectoryStore.directory }

    private var presentationMode: QuestionBankPresentationMode {
        get { QuestionBankPresentationMode(rawValue: storedPresentationMode) ?? .continuous }
        nonmutating set { storedPresentationMode = newValue.rawValue }
    }

    private func activateCrossPaperReaderIfNeeded() {
        let shouldBeVisible = isCrossPaperRouteVisible && rootTabSelection.wrappedValue == .questionBank
        isCrossPaperVisible = shouldBeVisible
        guard shouldBeVisible, needsIndexReload || readerDirectoryStore.directory == nil else { return }
        needsIndexReload = false
        crossPaperLoadGeneration &+= 1
    }

    private func requestCrossPaperReload() {
        needsIndexReload = true
        readerWindowError = nil
        pendingCrossQuestionIDs.removeAll()
        crossQuestionUpdateGeneration &+= 1
        readerWindowStore.cancel(clear: true)
        readerDirectoryStore.cancel(clear: true)
        refreshGroups()
        guard isCrossPaperVisible, rootTabSelection.wrappedValue == .questionBank else { return }
        needsIndexReload = false
        crossPaperLoadGeneration &+= 1
    }

    private func loadCrossPaperDirectory(generation: Int) async {
        guard generation == crossPaperLoadGeneration, isCrossPaperVisible,
              rootTabSelection.wrappedValue == .questionBank else { return }
        await readerDirectoryStore.loadCrossPaper(
            container: modelContext.container,
            filter: filter,
            paperID: paperID,
            scopedPaperIDs: scopedPaperIDs
        )
        guard generation == crossPaperLoadGeneration, isCrossPaperVisible,
              rootTabSelection.wrappedValue == .questionBank else { return }
        guard let directory else {
            needsIndexReload = true
            return
        }
        readerWindowStore.install(directory: directory)
        refreshGroups()
    }

    private func loadCrossPaperWindow(aroundQuestionID requestedID: String? = nil) async {
        guard isCrossPaperVisible, rootTabSelection.wrappedValue == .questionBank,
              let directory,
              let anchorID = requestedID ?? currentQuestionID ?? orderedItemIDs.first,
              directory.question(for: anchorID) != nil else { return }
        await readerWindowStore.loadWindow(
            container: modelContext.container,
            directory: directory,
            anchorID: anchorID,
            radius: presentationMode == .single
                ? QuestionBankReaderWindowBounds.singlePagePrefetchRadius
                : QuestionBankReaderWindowBounds.continuousPrefetchRadius
        )
        guard isCrossPaperVisible, rootTabSelection.wrappedValue == .questionBank else { return }
        var answerLoadError: String?
        do {
            try await answerStateStore.load(Array(readerWindowStore.questionsByCompoundID.keys), from: modelContext.container)
        } catch {
            answerLoadError = "作答状态加载失败：\(error.localizedDescription)"
        }
        readerWindowError = readerWindowStore.errorMessage ?? answerLoadError
        refreshWindowDependencies()
    }

    private func loadCrossPaperQuestionUpdates(generation: Int) async {
        guard generation == crossQuestionUpdateGeneration,
              isCrossPaperVisible,
              rootTabSelection.wrappedValue == .questionBank,
              !pendingCrossQuestionIDs.isEmpty,
              let directory else { return }
        let changedQuestionIDs = pendingCrossQuestionIDs
        let compoundIDs = Set(directory.questions.compactMap { entry in
            changedQuestionIDs.contains(entry.sourceCompoundID) ? entry.sourceCompoundID : nil
        })
        guard !compoundIDs.isEmpty else {
            pendingCrossQuestionIDs.subtract(changedQuestionIDs)
            return
        }
        let anchorID = currentQuestionID ?? directory.orderedIDs.first ?? ""
        await readerWindowStore.loadWindow(
            container: modelContext.container,
            directory: directory,
            anchorID: anchorID,
            radius: QuestionBankReaderWindowBounds.continuousPrefetchRadius,
            specificIDs: compoundIDs
        )
        guard generation == crossQuestionUpdateGeneration else { return }
        var answerLoadError: String?
        do {
            try await answerStateStore.load(Array(readerWindowStore.questionsByCompoundID.keys), from: modelContext.container)
        } catch {
            answerLoadError = "作答状态加载失败：\(error.localizedDescription)"
        }
        readerWindowError = readerWindowStore.errorMessage ?? answerLoadError
        pendingCrossQuestionIDs.subtract(changedQuestionIDs)
        if reloadCrossWindowAfterQuestionUpdate {
            reloadCrossWindowAfterQuestionUpdate = false
            crossWindowLoadGeneration &+= 1
        }
    }

    private func makeGroups(using directory: QuestionBankReaderDirectorySnapshot) -> [QuestionBankCrossPaperGroup] {
        let grouped = Dictionary(grouping: directory.questions, by: \.paperID)
        let orderedPaperIDs = directory.questions.reduce(into: [String]()) { result, item in
            if result.last != item.paperID { result.append(item.paperID) }
        }
        return orderedPaperIDs.compactMap { paperID in
            guard let questions = grouped[paperID], !questions.isEmpty else { return nil }
            let paper = directory.paperSummariesByID[paperID]
            let title = paper?.title ?? "未命名试卷"
            let items = questions.map { entry -> QuestionBankHomeQuestion in
                let coarseModule = QuestionBankCoarseModule(rawValue: entry.coarseModule) ?? .uncategorized
                let question = QuestionBankQuestion(
                    id: entry.questionID,
                    paperID: entry.paperID,
                    moduleID: entry.moduleID,
                    number: entry.originalNumber,
                    subject: entry.coarseModule,
                    type: entry.coarseQuestionType,
                    materialID: entry.materialID,
                    stem: "",
                    stemImageAssetID: "",
                    options: [],
                    answer: "",
                    explanation: "",
                    originalPage: "",
                    isDifficult: entry.isDifficult,
                    needsReview: entry.needsReview,
                    knowledgePoints: entry.knowledgePoints,
                    weaknessTags: entry.weaknessTags
                )
                let record = QuestionBankRecord(
                    compoundID: entry.sourceCompoundID,
                    paperID: entry.paperID,
                    kind: QuestionBankRepository.questionKind,
                    stableID: entry.questionID,
                    moduleID: entry.moduleID,
                    questionNumber: entry.originalNumber,
                    sequence: entry.moduleSequence,
                    title: title,
                    payload: Data(),
                    contentRevision: entry.sourceRevision
                )
                return QuestionBankHomeQuestion(
                    record: record,
                    question: question,
                    module: coarseModule,
                    questionTypeFilter: entry.coarseQuestionType,
                    moduleID: entry.moduleID,
                    moduleTitle: entry.moduleTitle,
                    moduleSequence: entry.moduleSequence,
                    isReaderBodyLoaded: false
                )
            }
            var emittedMaterials = Set<String>()
            var steps: [QuestionBankCrossPaperStep] = []
            for item in items {
                let materialID = item.question.materialID
                if !materialID.isEmpty, emittedMaterials.insert(materialID).inserted {
                    steps.append(QuestionBankCrossPaperStep(
                        id: "\(paperID)::material::\(materialID)",
                        materialID: materialID,
                        material: nil,
                        question: nil
                    ))
                }
                steps.append(QuestionBankCrossPaperStep(
                    id: item.id, materialID: nil, material: nil, question: item
                ))
            }
            return QuestionBankCrossPaperGroup(
                paperID: paperID,
                title: title,
                steps: steps,
                questions: items,
                materialsByID: Dictionary(
                    readerWindowStore.materialsByCompoundID.values
                        .filter { $0.paperID == paperID }
                        .map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                ),
                sourcePapers: readerWindowStore.sourcePapersByID[paperID] ?? []
            )
        }
    }

    private func refreshGroups() {
        guard let directory else {
            groups = []
            orderedItems = []
            orderedItemIDs = []
            itemsByID = [:]
            groupsByPaperID = [:]
            localOrdinalByID = [:]
            orderedOrdinalByID = [:]
            overviewGroups = []
            currentQuestionID = nil
            return
        }
        let currentGroups = makeGroups(using: directory)
        let flattenedItems = currentGroups.flatMap(\.questions)
        groups = currentGroups
        orderedItems = flattenedItems
        orderedItemIDs = flattenedItems.map(\.id)
        itemsByID = Dictionary(flattenedItems.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        groupsByPaperID = Dictionary(currentGroups.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
        localOrdinalByID = Dictionary(
            flattenedItems.enumerated().map { ($1.id, $0 + 1) },
            uniquingKeysWith: { first, _ in first }
        )
        orderedOrdinalByID = localOrdinalByID
        let paperTitles = directory.paperSummariesByID.mapValues(\.title)
        overviewGroups = QuestionBankOverviewGrouping.groups(from: flattenedItems.map { item in
            QuestionBankOverviewCandidate(
                id: item.id,
                paperID: item.record.paperID,
                paperTitle: paperTitles[item.record.paperID] ?? "未命名试卷",
                questionNumber: displayNumber(for: item),
                moduleID: item.moduleID ?? item.question.moduleID,
                moduleTitle: item.moduleTitle ?? "",
                moduleSequence: item.moduleSequence,
                type: item.question.type,
                subject: item.question.subject
            )
        })
        if !itemsByID.keys.contains(currentQuestionID ?? "") {
            currentQuestionID = flattenedItems.first?.id
        }
    }

    private func refreshWindowDependencies() {
        groups = groups.map { group in
            QuestionBankCrossPaperGroup(
                paperID: group.paperID,
                title: group.title,
                steps: group.steps,
                questions: group.questions,
                materialsByID: Dictionary(
                    readerWindowStore.materialsByCompoundID.values
                        .filter { $0.paperID == group.paperID }
                        .map { ($0.id, $0) },
                    uniquingKeysWith: { first, _ in first }
                ),
                sourcePapers: readerWindowStore.sourcePapersByID[group.paperID] ?? []
            )
        }
        groupsByPaperID = Dictionary(groups.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var currentItem: QuestionBankHomeQuestion? {
        readerItem(for: currentQuestionID ?? "") ?? orderedItems.first.map(materializedItem)
    }

    private func readerItem(for id: String) -> QuestionBankHomeQuestion? {
        guard let directoryItem = itemsByID[id] else { return nil }
        return materializedItem(directoryItem)
    }

    private func materializedItem(_ directoryItem: QuestionBankHomeQuestion) -> QuestionBankHomeQuestion {
        guard let loaded = readerWindowStore.question(for: directoryItem.id) else { return directoryItem }
        return QuestionBankHomeQuestion(
            record: directoryItem.record,
            question: loaded.question,
            module: directoryItem.module,
            questionTypeFilter: directoryItem.questionTypeFilter,
            moduleID: directoryItem.moduleID,
            moduleTitle: directoryItem.moduleTitle,
            moduleSequence: directoryItem.moduleSequence,
            isReaderBodyLoaded: true
        )
    }

    private var singlePositionText: String {
        "\(orderedOrdinalByID[currentQuestionID ?? ""] ?? 1)/\(orderedItems.count)"
    }

    private func adjacentQuestionID(from id: String, direction: Int) -> String? {
        guard let ordinal = orderedOrdinalByID[id] else { return nil }
        let adjacentOffset = ordinal - 1 + direction
        guard orderedItemIDs.indices.contains(adjacentOffset) else { return nil }
        return orderedItemIDs[adjacentOffset]
    }

    var body: some View {
        readerScreen
            .overlay {
                QuestionBankDoodleAutosaveObserver(session: doodleSession, context: modelContext)
            }
            .onAppear {
                isCrossPaperRouteVisible = true
                activateCrossPaperReaderIfNeeded()
            }
            .task(id: "legacy-cross-answer-migration|\(legacyAnswerStorageKey)") {
                await migrateLegacyAnswerStateIfNeeded()
            }
            .task(id: "\(crossPaperLoadGeneration)|\(isCrossPaperVisible)") {
                await loadCrossPaperDirectory(generation: crossPaperLoadGeneration)
            }
            .task(id: "\(currentQuestionID ?? "")|\(crossPaperLoadGeneration)|\(crossWindowLoadGeneration)|\(isCrossPaperVisible)|\(presentationMode.rawValue)") {
                await loadCrossPaperWindow()
            }
            .task(id: crossQuestionUpdateGeneration) {
                await loadCrossPaperQuestionUpdates(generation: crossQuestionUpdateGeneration)
            }
            .onReceive(NotificationCenter.default.publisher(for: QuestionBankRecordChangeSignal.notification)) { notification in
                guard scopedPaperIDs?.isEmpty != true,
                      QuestionBankRecordChangeSignal.affectsAny(scopedPaperIDs ?? [], notification: notification) else { return }
                if let changes = QuestionBankRecordChangeSignal.recordChanges(notification: notification),
                   changes.allSatisfy({ $0.kind == .questionAnalysis || $0.kind == .questionLinks }) {
                    let scopedChanges = changes.filter {
                        scopedPaperIDs == nil || scopedPaperIDs?.contains($0.paperID) == true
                    }
                    if readerWindowStore.isLoading {
                        reloadCrossWindowAfterQuestionUpdate = true
                        readerWindowStore.cancel(clear: false)
                    }
                    pendingCrossQuestionIDs.formUnion(scopedChanges.compactMap { change in
                        change.recordID.isEmpty
                            ? nil
                            : "\(change.paperID)::\(QuestionBankRepository.questionKind)::\(change.recordID)"
                    })
                    crossQuestionUpdateGeneration &+= 1
                } else {
                    requestCrossPaperReload()
                }
            }
            .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
                if selectedTab == .questionBank {
                    activateCrossPaperReaderIfNeeded()
                } else {
                    isCrossPaperVisible = false
                    readerDirectoryStore.cancel(clear: false)
                    readerWindowStore.cancel(clear: true)
                    refreshWindowDependencies()
                }
            }
            .onChange(of: filter) { _, _ in requestCrossPaperReload() }
            .onReceive(NotificationCenter.default.publisher(for: QuestionBankAnswerStateRepository.changeNotification)) { notification in
                refreshOverviewAnswerStates(for: notification)
            }
            .onChange(of: presentationMode) { _, mode in
                if mode != .continuous { continuousQuestionDoodleRecordID = nil }
            }
            .onChange(of: doodleSession.isPresented) { _, isPresented in
                if !isPresented { continuousQuestionDoodleRecordID = nil }
            }
            .onChange(of: scenePhase) { oldPhase, phase in
                switch phase {
                case .background:
                    doodleSession.canvas.controller.invalidateDecodedDrawing()
                case .active where oldPhase == .background:
                    QuestionBankDoodleMemoryCache.shared.invalidate()
                    doodleSession.canvas.controller.invalidateDecodedDrawing()
                default:
                    break
                }
            }
            .onDisappear {
                isCrossPaperRouteVisible = false
                isCrossPaperVisible = false
                readerDirectoryStore.cancel(clear: false)
                readerWindowStore.cancel(clear: true)
                refreshWindowDependencies()
            }
            .alert("答案更新", isPresented: Binding(
                get: { missingAnswerEditError != nil || missingAnswerEditConfirmation != nil },
                set: {
                    if !$0 {
                        missingAnswerEditError = nil
                        missingAnswerEditConfirmation = nil
                    }
                }
            )) {
                Button("好", role: .cancel) {
                    missingAnswerEditError = nil
                    missingAnswerEditConfirmation = nil
                }
            } message: {
                Text(missingAnswerEditError ?? missingAnswerEditConfirmation ?? "")
            }
    }

    private var readerScreen: some View {
        Group {
            if directory == nil {
                if let error = readerDirectoryStore.errorMessage {
                    VStack(spacing: 12) {
                        ContentUnavailableView(
                            "题目目录加载失败",
                            systemImage: "exclamationmark.triangle",
                            description: Text(error)
                        )
                        Button("重试") { requestCrossPaperReload() }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView("正在准备题目…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                GeometryReader { geometry in
                    readerPage(width: geometry.size.width, height: geometry.size.height)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            if showsReaderOptions {
                readerOptionsOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .animation(.easeOut(duration: 0.16), value: showsReaderOptions)
        .background(Color.white)
        .navigationTitle(presentationMode == .single ? "" : (paperTitle ?? filter.module?.rawValue ?? "多卷题目"))
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .secondaryPageTabBarHidden()
        .toolbar { readerToolbar }
        .sheet(isPresented: $showsOverview) { questionOverviewSheet }
        .sheet(item: $activeQuestionDetail) { questionDetailSheet(for: $0) }
        .overlay(alignment: .top) {
            if let readerWindowError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.danger)
                    Text("题目窗口加载失败：\(readerWindowError)")
                        .font(AppTheme.auxiliaryFont)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                    Button("重试") { Task { await loadCrossPaperWindow() } }
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
        }
    }

    @ToolbarContentBuilder
    private var readerToolbar: some ToolbarContent {
            if presentationMode == .single {
                ToolbarItem(placement: .principal) {
                    Button {
                        guard let currentItem, !doodleSession.isPresented else { return }
                        activeQuestionDetail = QuestionBankCrossPaperDetailRoute(questionID: currentItem.id)
                    } label: {
                        Text(singlePositionText)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(currentItem.map {
                        "打开第\(displayNumber(for: $0))题详情，当前进度\(singlePositionText)"
                    } ?? "当前题进度")
                    .accessibilityHint("打开当前题目详情")
                    .accessibilityIdentifier("question-bank-single-position")
                    .disabled(currentItem?.isReaderBodyLoaded != true || doodleSession.isPresented)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 0) {
                    if presentationMode == .single { doodleButton }
                    Button {
                        guard !doodleSession.isPresented else { return }
                        showQuestionOverview()
                    } label: {
                        Image(systemName: "square.grid.3x3")
                            .font(.system(size: 14, weight: .medium))
                            .frame(width: 44, height: 44)
                            .foregroundStyle(AppTheme.accent.opacity(0.86))
                    }
                    .accessibilityLabel("题号总览")
                    .accessibilityIdentifier("question-bank-number-overview")
                    .disabled(orderedItems.isEmpty || doodleSession.isPresented)
                    readerOptionsButton
                }
                .id(doodleSession.isPresented ? "cross-paper-toolbar-doodle" : "cross-paper-toolbar-reader")
            }
            .documentToolbarBackground()
    }

    private var questionOverviewSheet: some View {
            NavigationStack {
                List {
                    ForEach(overviewGroups.indices, id: \.self) { index in
                        let group = overviewGroups[index]
                        let startsPaper = index == 0 || overviewGroups[index - 1].paperID != group.paperID
                        Section {
                            ForEach(group.questions) { candidate in
                                Button {
                                    presentationMode = .single
                                    currentQuestionID = candidate.id
                                    showsOverview = false
                                } label: {
                                    HStack {
                                        if let item = itemsByID[candidate.id] {
                                            QuestionBankNumberStatusCircle(
                                                number: candidate.questionNumber,
                                                status: overviewAnswerStatus(for: item),
                                                isCurrent: item.id == currentQuestionID,
                                                diameter: 30
                                            )
                                        }
                                        Text("第\(candidate.questionNumber)题")
                                        Spacer()
                                        if let item = itemsByID[candidate.id],
                                           let heading = QuestionBankQuestionHeading.displayLabel(
                                            type: item.question.type,
                                            subject: item.question.subject,
                                            moduleTitle: item.moduleTitle
                                        ) {
                                            Text(heading).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                                .accessibilityLabel("\(group.moduleTitle)，第\(candidate.questionNumber)题")
                                .accessibilityValue(itemsByID[candidate.id]
                                    .map { overviewAnswerStatus(for: $0).accessibilityValue } ?? "未判定")
                                .accessibilityIdentifier("question-bank-cross-paper-overview-\(candidate.id)")
                            }
                        } header: {
                            VStack(alignment: .leading, spacing: 3) {
                                if paperID == nil && startsPaper {
                                    Text(group.paperTitle)
                                        .font(AppTheme.auxiliaryFont)
                                }
                                HStack(spacing: 6) {
                                    if group.startsModule { Text(group.moduleTitle) }
                                    if let type = group.coarseQuestionType {
                                        Text(type)
                                    }
                                }
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                            }
                        }
                    }
                }
                .navigationTitle("题号总览")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsOverview = false }
                    }
                }
            }
    }

    @ViewBuilder
    private func questionDetailSheet(for route: QuestionBankCrossPaperDetailRoute) -> some View {
        if let item = readerItem(for: route.questionID),
           let group = groupsByPaperID[item.record.paperID], item.isReaderBodyLoaded {
            let record = persistedQuestionRecord(for: item) ?? item.record
            let detailContext = questionAnalysisContext(for: item, group: group, record: record)
            if detailContext.typeMapping.subject == "申论" {
                QuestionBankQuestionDetailPanel(
                    question: item.question,
                    title: "第\(item.question.number)题详情",
                    isDoodlePresented: doodleSession.isPresented,
                    onDone: { activeQuestionDetail = nil },
                    onClearAnswer: { clearAnswer(for: item.record.compoundID) },
                    onSave: { stem, optionTexts, annotations in
                        try QuestionBankRepository.updateQuestionText(
                            paperID: item.record.paperID,
                            questionID: item.question.id,
                            stem: stem,
                            optionTexts: optionTexts,
                            annotations: annotations,
                            moduleTitle: item.moduleTitle,
                            context: modelContext
                        )
                    }
                ) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if let material = group.materialsByID[item.question.materialID] {
                                materialSection(
                                    material,
                                    paperID: group.paperID,
                                    sourcePapers: group.sourcePapers
                                )
                            }
                            questionSection(
                                item,
                                group: group,
                                showsPaperHeading: false,
                                showsQuestionNumber: false,
                                showsDoodleCanvas: false
                            )
                            QuestionBankProvenanceDisclosure(
                                title: "题目来源",
                                entries: item.question.provenance ?? [],
                                sourcePapers: group.sourcePapers
                            )
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                    .background(Color.white)
                    .scrollDisabled(doodleSession.isPresented)
                    .coordinateSpace(name: "question-bank-cross-paper-scroll")
                }
            } else {
                NavigationStack {
                    LibraryRecordDetailView(
                        questionBankContext: detailContext,
                        onEdit: {},
                        onClearAnswer: { clearAnswer(for: item.record.compoundID) },
                        onDone: { activeQuestionDetail = nil }
                    )
                }
                .presentationDetents([.large])
            }
        } else if itemsByID[route.questionID] != nil {
            ProgressView("正在加载题目…")
                .task { await loadCrossPaperWindow(aroundQuestionID: route.questionID) }
        } else {
            ContentUnavailableView("题目不存在", systemImage: "doc.text.magnifyingglass")
        }
    }

    private func questionAnalysisContext(
        for item: QuestionBankHomeQuestion,
        group: QuestionBankCrossPaperGroup,
        record: QuestionBankRecord? = nil
    ) -> QuestionBankQuestionAnalysisContext {
        let answerStateID = item.record.compoundID
        let selectedOptionID = selectedAnswerOption(for: answerStateID)
        let answerRevealed = readingMode == .reading || readingMode.revealsAnswer(
            afterSelecting: selectedOptionID,
            wasConfirmed: isAnswerRevealed(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        let assets = Dictionary(
            readerWindowStore.assetsByCompoundID.values
                .filter { $0.paperID == item.record.paperID }
                .map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return QuestionBankQuestionAnalysisContext(
            record: record ?? item.record,
            question: item.question,
            moduleTitle: item.moduleTitle,
            material: group.materialsByID[item.question.materialID],
            sourcePapers: group.sourcePapers,
            assetsByID: assets,
            selectedOptionID: selectedOptionID,
            isAnswerRevealed: answerRevealed
        )
    }

    private func persistedQuestionRecord(for item: QuestionBankHomeQuestion) -> QuestionBankRecord? {
        let compoundID = item.record.compoundID
        var descriptor = FetchDescriptor<QuestionBankRecord>(
            predicate: #Predicate { $0.compoundID == compoundID }
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func readerPage(width: CGFloat, height: CGFloat) -> some View {
        Group {
            if presentationMode == .single, let item = currentItem {
                singleReader(item, pageHeight: height)
            } else {
                continuousReader
            }
        }
        .frame(width: width, height: height)
        .overlay { continuousQuestionDoodleLayer(height: height) }
    }

    @ViewBuilder
    private func continuousQuestionDoodleLayer(height: CGFloat) -> some View {
        if presentationMode == .continuous,
           doodleSession.isPresented,
           let recordID = continuousQuestionDoodleRecordID,
           doodleSession.targetRecordID == recordID {
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: recordID,
                minimumCanvasHeight: height
            )
        }
    }

    private var paperTitle: String? {
        guard let paperID else { return nil }
        return directory?.paperSummariesByID[paperID]?.title
    }

    private var doodleButton: some View {
        Button {
            guard let item = currentItem, !doodleSession.isPresented else { return }
            presentDoodle(for: item)
        } label: {
            Image(systemName: "pencil.and.scribble")
                .font(.system(size: 17, weight: .regular))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(currentItem.map { "标注当前题（第\(displayNumber(for: $0))题）" } ?? "标注当前题")
        .accessibilityIdentifier("question-bank-doodle-current-question")
        .disabled(currentItem == nil || doodleSession.isPresented)
    }

    private var readerOptionsButton: some View {
        Button {
            guard !doodleSession.isPresented else { return }
            showsReaderOptions.toggle()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 44, height: 44)
                .foregroundStyle(AppTheme.accent)
        }
        .accessibilityLabel("阅读设置")
        .accessibilityValue("浏览方式：\(presentationMode.title)，答题方式：\(readingMode.title)，选择后确认答案：\(requiresAnswerConfirmation ? "开启" : "关闭")")
        .accessibilityIdentifier("question-bank-reader-options")
        .disabled(doodleSession.isPresented)
    }

    private var readerOptionsOverlay: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { showsReaderOptions = false }
            QuestionBankReaderOptionsPopover(
                presentationMode: Binding(
                    get: { presentationMode },
                    set: {
                        presentationMode = $0
                        showsReaderOptions = false
                    }
                ),
                readingMode: Binding(
                    get: { readingMode },
                    set: {
                        readingMode = $0
                        showsReaderOptions = false
                    }
                ),
                requiresAnswerConfirmation: Binding(
                    get: { requiresAnswerConfirmation },
                    set: { setAnswerConfirmationEnabled($0) }
                ),
                currentQuestionTitle: currentItem.map { "第\(displayNumber(for: $0))题" },
                onClearCurrentQuestion: {
                    guard let item = currentItem else { return }
                    clearAnswer(for: item.record.compoundID)
                },
                onDismiss: { showsReaderOptions = false }
            )
            .padding(.top, 6)
            .padding(.trailing, 8)
        }
    }

    private var continuousReader: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if groups.isEmpty {
                    ContentUnavailableView("没有符合条件的题目", systemImage: "text.book.closed")
                }
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 0) {
                        paperDivider(group.title, count: group.questions.count)
                        ForEach(group.steps) { step in
                            if let materialID = step.materialID,
                               let material = group.materialsByID[materialID] {
                                materialSection(material, paperID: group.paperID, sourcePapers: group.sourcePapers)
                            } else if step.materialID != nil {
                                ProgressView("正在加载共用材料…")
                                    .frame(maxWidth: .infinity, minHeight: 72)
                            } else if let item = step.question {
                                questionSection(
                                    readerItem(for: item.id) ?? item,
                                    group: group,
                                    showsPaperHeading: false,
                                    showsDoodleCanvas: false,
                                    showsDoodleButton: true,
                                    showsQuestionType: false
                                )
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color.white)
        .scrollDisabled(doodleSession.isPresented)
        .coordinateSpace(name: "question-bank-cross-paper-scroll")
        .onPreferenceChange(QuestionBankReaderViewportPreference.self) { frames in
            let visible = frames.filter { $0.value.bottom > 0 }
                .min { abs($0.value.top) < abs($1.value.top) }
            if let visible { currentQuestionID = visible.key }
        }
    }

    private func singleReader(_ item: QuestionBankHomeQuestion, pageHeight: CGFloat) -> some View {
        return QuestionBankInteractivePageDeck(
            currentID: item.id,
            previousID: adjacentQuestionID(from: item.id, direction: -1),
            nextID: adjacentQuestionID(from: item.id, direction: 1),
            isEnabled: !doodleSession.isPresented,
            onCommit: moveQuestion(to:)
        ) { pageID, isPageInactiveOrDragging in
            if let pageItem = readerItem(for: pageID),
               let group = groupsByPaperID[pageItem.record.paperID] {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if group.questions.first?.id == pageItem.id {
                            paperDivider(group.title, count: group.questions.count)
                        }
                        if !pageItem.question.materialID.isEmpty,
                           let material = group.materialsByID[pageItem.question.materialID] {
                            materialSection(material, paperID: group.paperID, sourcePapers: group.sourcePapers)
                        }
                        questionSection(
                            pageItem,
                            group: group,
                            showsPaperHeading: false,
                            showsQuestionNumber: false,
                            showsDoodleCanvas: false,
                            showsQuestionType: false,
                            reportsVisibility: !isPageInactiveOrDragging
                        )
                    }
                    .frame(maxWidth: .infinity, minHeight: pageHeight, alignment: .topLeading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .overlay {
                        LibraryDoodleContentLayer(
                            session: doodleSession,
                            targetRecordID: QuestionBankDoodleRepository.recordID(
                                paperID: pageItem.record.paperID,
                                scope: .question(pageItem.question.id)
                            ),
                            minimumCanvasHeight: pageHeight
                        )
                    }
                }
                .background(Color.white)
                .scrollDisabled(doodleSession.isPresented || isPageInactiveOrDragging)
                .scrollBounceBehavior(.basedOnSize)
                .coordinateSpace(name: "question-bank-cross-paper-scroll")
                .accessibilityIdentifier("question-bank-single-page-scroll")
            } else {
                Color.clear
            }
        }
    }

    private func paperDivider(_ title: String, count: Int) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(AppTheme.sectionTitleFont)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)题")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.55)).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("question-bank-paper-divider-\(title)")
    }

    private func materialSection(
        _ material: QuestionBankMaterial,
        paperID: String,
        sourcePapers: [QuestionBankSourcePaper]
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(material.type.isEmpty ? "共用材料" : material.type)
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
            if !material.text.isEmpty {
                Text(verbatim: material.text)
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !material.imageAssetID.isEmpty,
               let asset = assetRecord(for: material.imageAssetID, paperID: paperID) {
                QuestionBankLocalImage(asset: asset, sizing: .material)
            }
            QuestionBankProvenanceDisclosure(
                title: "材料来源", entries: material.provenance ?? [], sourcePapers: sourcePapers
            )
            LibraryDoodleContentLayer(
                session: doodleSession,
                targetRecordID: QuestionBankDoodleRepository.recordID(
                    paperID: paperID, scope: .material(material.id)
                ),
                minimumCanvasHeight: 0
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.35)).frame(height: 1)
        }
    }

    private func questionSection(
        _ item: QuestionBankHomeQuestion,
        group: QuestionBankCrossPaperGroup,
        showsPaperHeading: Bool,
        showsQuestionNumber: Bool = true,
        showsDoodleCanvas: Bool = true,
        showsDoodleButton: Bool = false,
        showsQuestionType: Bool = true,
        reportsVisibility: Bool = true
    ) -> some View {
        let answerStateID = item.record.compoundID
        let selected = selectedAnswerOption(for: answerStateID)
        let hasAnswer = !item.question.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let showsGraphLayout = QuestionBankCoarseModule.classify(
            explicitModuleTitle: item.moduleTitle
        ) == .reasoning
        let reveals = readingMode.revealsAnswer(
            afterSelecting: selected,
            wasConfirmed: isAnswerRevealed(answerStateID),
            requiresConfirmation: requiresAnswerConfirmation
        )
        let heading = showsQuestionType ? QuestionBankQuestionHeading.displayLabel(
            type: item.question.type,
            subject: item.question.subject,
            moduleTitle: item.moduleTitle
        ) : nil
        return VStack(alignment: .leading, spacing: 8) {
            if showsPaperHeading, group.questions.first?.id == item.id {
                paperDivider(group.title, count: group.questions.count)
            }
            if showsQuestionNumber || heading != nil {
                HStack(spacing: 8) {
                    if showsQuestionNumber { questionNumberButton(for: item) }
                    if let heading {
                        Text(heading)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if showsDoodleButton {
                        Button { presentDoodle(for: item) } label: {
                            Image(systemName: "pencil.and.scribble")
                                .font(.system(size: 16, weight: .regular))
                                .frame(width: 40, height: 40)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(AppTheme.accent)
                        .accessibilityLabel("标注第\(displayNumber(for: item))题")
                        .accessibilityHint("仅标注这道题")
                        .accessibilityIdentifier("question-bank-doodle-question-\(item.id)")
                        .disabled(doodleSession.isPresented)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                QuestionBankQuestionAnnotationBadges(question: item.question)
                if !item.question.stem.isEmpty {
                    Text(verbatim: item.question.stem)
                        .font(QuestionBankTypography.contentFont)
                        .lineSpacing(QuestionBankTypography.contentLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !item.question.stemImageAssetID.isEmpty,
                   let asset = assetRecord(for: item.question.stemImageAssetID, paperID: item.record.paperID) {
                    QuestionBankLocalImage(asset: asset, sizing: showsGraphLayout ? .graph : .stem)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    questionID: item.question.id,
                    option: option,
                    answer: item.question.answer,
                    readingMode: readingMode,
                    selectedOptionID: selected,
                    revealsAnswer: reveals,
                    isSelectionLocked: readingMode == .practice && selected != nil,
                    isInteractionBlocked: doodleSession.isPresented || !answerStateStore.isLoaded(answerStateID),
                    showsGraphLayout: showsGraphLayout,
                    onSelect: { selectOption(option.id, item: item) },
                    assetLookup: { assetRecord(for: $0, paperID: item.record.paperID) }
                )
            }
            if readingMode == .reading, hasAnswer {
                Label("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)", systemImage: "checkmark.circle.fill")
                    .font(QuestionBankTypography.contentFont)
                    .foregroundStyle(QuestionBankAnswerFeedbackPalette.correct)
                    .padding(.top, 6)
            } else if reveals, let selected, hasAnswer {
                HStack(spacing: 8) {
                    Text("你的选择：\(selected)")
                        .foregroundStyle(selected == item.question.answer
                            ? QuestionBankAnswerFeedbackPalette.correct
                            : QuestionBankAnswerFeedbackPalette.incorrect)
                    Spacer(minLength: 8)
                    Text("正确答案：\(item.question.answer.isEmpty ? "未提供" : item.question.answer)")
                        .fontWeight(.semibold)
                        .foregroundStyle(QuestionBankAnswerFeedbackPalette.correct)
                }
                .font(AppTheme.auxiliaryFont)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("question-bank-answer-feedback-\(item.id)")
                QuestionBankAnswerFollowUpAction(
                    analysis: questionAnalysisContext(for: item, group: group)
                )
                .padding(.top, 7)
            } else if readingMode == .practice && requiresAnswerConfirmation {
                HStack {
                    Spacer()
                    Button("确认答案") { confirmAnswer(for: answerStateID) }
                        .buttonStyle(.borderedProminent)
                        .disabled(selected == nil || doodleSession.isPresented)
                        .accessibilityLabel("确认答案并查看正确选项")
                        .accessibilityIdentifier("question-bank-confirm-answer-\(item.id)")
                }
                .padding(.top, 6)
                if selected == nil {
                    QuestionBankAnswerFollowUpAction(
                        analysis: questionAnalysisContext(for: item, group: group),
                        categoryOverride: .cannotSolve
                    )
                    .padding(.top, 6)
                }
            } else if readingMode == .practice && selected == nil {
                QuestionBankAnswerFollowUpAction(
                    analysis: questionAnalysisContext(for: item, group: group),
                    categoryOverride: .cannotSolve
                )
                .padding(.top, 6)
            }
            if hasAnswer && (readingMode == .reading || reveals) {
                QuestionBankReferenceAccuracyControl(
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    accuracy: item.question.accuracy
                )
                    .padding(.top, 5)
                    .transition(.opacity)
            }
            if !hasAnswer {
                QuestionBankMissingAnswerMenu(questionID: item.id, options: item.question.options) { answer in
                    setMissingAnswer(answer, for: item)
                }
                .padding(.top, 4)
            }
            if let material = group.materialsByID[item.question.materialID] {
                QuestionBankProvenanceDisclosure(
                    title: "材料来源", entries: material.provenance ?? [], sourcePapers: group.sourcePapers
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .background {
            if reportsVisibility {
                GeometryReader { geometry in
                    let frame = geometry.frame(in: .named("question-bank-cross-paper-scroll"))
                    Color.clear.preference(
                        key: QuestionBankReaderViewportPreference.self,
                        value: [item.id: QuestionBankReaderViewportFrame(top: frame.minY, bottom: frame.maxY)]
                    )
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Color(uiColor: .separator).opacity(0.4)).frame(height: 1)
        }
        .overlay {
            if showsDoodleCanvas {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: QuestionBankDoodleRepository.recordID(
                        paperID: item.record.paperID, scope: .question(item.question.id)
                    ),
                    minimumCanvasHeight: 0
                )
            }
        }
        .frame(minHeight: item.isReaderBodyLoaded ? 0 : 108)
        .overlay {
            if !item.isReaderBodyLoaded {
                ProgressView("正在加载题目…")
                    .font(AppTheme.auxiliaryFont)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.white.opacity(0.96))
                    .allowsHitTesting(false)
            }
        }
        .disabled(!item.isReaderBodyLoaded)
        .id(item.id)
    }

    private func questionNumberButton(for item: QuestionBankHomeQuestion) -> some View {
        let displayNumber = displayNumber(for: item)
        return Button {
            guard item.isReaderBodyLoaded, !doodleSession.isPresented else { return }
            activeQuestionDetail = QuestionBankCrossPaperDetailRoute(questionID: item.id)
        } label: {
            Text("\(displayNumber).")
                .font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("打开第\(displayNumber)题详情")
        .accessibilityHint("查看题干、选项和解析")
        .accessibilityIdentifier("question-bank-question-detail-\(item.id)")
        .disabled(!item.isReaderBodyLoaded || doodleSession.isPresented)
    }

    private func displayNumber(for item: QuestionBankHomeQuestion) -> Int {
        QuestionBankDisplayNumber.resolve(
            originalNumber: item.question.number,
            localOrdinal: localOrdinalByID[item.id],
            usesLocalOrdinal: paperID != nil && (filter.module != nil || !filter.questionType.isEmpty)
        )
    }

    private func overviewAnswerStatus(for item: QuestionBankHomeQuestion) -> QuestionBankOverviewAnswerStatus {
        QuestionBankOverviewAnswerStatus.resolve(
            selectedOptionID: overviewAnswerStatesByID[item.record.compoundID]?.selectedOptionID,
            answer: item.question.answer,
            isConfirmed: overviewAnswerStatesByID[item.record.compoundID]?.isRevealed == true
        )
    }

    private func showQuestionOverview() {
        guard !doodleSession.isPresented else { return }
        let ids = orderedItemIDs
        Task {
            do {
                overviewAnswerStatesByID = try await QuestionBankAnswerStateRepository.read(
                    compoundIDs: ids,
                    from: modelContext.container
                )
                showsOverview = true
            } catch {
                readerWindowError = "题号总览作答状态加载失败：\(error.localizedDescription)"
            }
        }
    }

    private func refreshOverviewAnswerStates(for notification: Notification) {
        if notification.userInfo?[QuestionBankAnswerStateRepository.resetKey] as? Bool == true {
            overviewAnswerStatesByID.removeAll()
            let currentIDs = Array(readerWindowStore.questionsByCompoundID.keys)
            Task {
                await Task.yield()
                do {
                    try await answerStateStore.load(currentIDs, from: modelContext.container)
                } catch {
                    readerWindowError = "作答状态重新加载失败：\(error.localizedDescription)"
                }
            }
            return
        }
        guard showsOverview else { return }
        let visibleIDs = Set(orderedItemIDs)
        let changedIDs = notification.userInfo?[QuestionBankAnswerStateRepository.changedIDsKey] as? [String] ?? []
        let affectedIDs = changedIDs.filter { visibleIDs.contains($0) }
        guard !affectedIDs.isEmpty else { return }
        if notification.userInfo?[QuestionBankAnswerStateRepository.clearedKey] as? Bool == true {
            for id in affectedIDs { overviewAnswerStatesByID.removeValue(forKey: id) }
            return
        }
        Task {
            do {
                let values = try await QuestionBankAnswerStateRepository.read(
                    compoundIDs: affectedIDs,
                    from: modelContext.container
                )
                overviewAnswerStatesByID.merge(values) { _, newest in newest }
                for id in affectedIDs where values[id] == nil { overviewAnswerStatesByID.removeValue(forKey: id) }
            } catch {
                readerWindowError = "题号总览作答状态刷新失败：\(error.localizedDescription)"
            }
        }
    }

    private func selectedAnswerOption(for compoundID: String) -> String? {
        answerStateStore.value(for: compoundID)?.selectedOptionID
    }

    private func isAnswerRevealed(_ compoundID: String) -> Bool {
        answerStateStore.value(for: compoundID)?.isRevealed == true
    }

    private func moveQuestion(to target: String) {
        guard !doodleSession.isPresented, itemsByID[target] != nil else { return }
        currentQuestionID = target
    }

    private func migrateLegacyAnswerStateIfNeeded() async {
        let selectedSnapshot = selectedOptionsJSON
        let revealedSnapshot = revealedAnswersJSON
        do {
            try await answerStateStore.migrateGlobalIfNeeded(in: modelContext.container)
            try await answerStateStore.migrateSceneStorageIfNeeded(
                sourceKey: legacyAnswerStorageKey,
                selectedOptionsJSON: selectedSnapshot,
                revealedAnswersJSON: revealedSnapshot,
                paperID: paperID,
                in: modelContext.container
            )
            if selectedOptionsJSON == selectedSnapshot { selectedOptionsJSON = "{}" }
            if revealedAnswersJSON == revealedSnapshot { revealedAnswersJSON = "[]" }
        } catch {
            readerWindowError = "旧作答数据迁移失败，原始备份已保留：\(error.localizedDescription)"
        }
    }

    private func clearAnswer(for questionID: String) {
        Task {
            do {
                try await answerStateStore.clear([questionID], in: modelContext.container)
            } catch {
                readerWindowError = "清除作答状态失败：\(error.localizedDescription)"
            }
        }
    }

    private func selectOption(_ optionID: String, item: QuestionBankHomeQuestion) {
        let answerStateID = item.record.compoundID
        guard !doodleSession.isPresented, readingMode == .practice,
              answerStateStore.isLoaded(answerStateID),
              !isAnswerRevealed(answerStateID) else { return }
        guard selectedAnswerOption(for: answerStateID) == nil else { return }
        Task {
            do {
                try await answerStateStore.setSelection(
                    optionID,
                    for: answerStateID,
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    revealed: !requiresAnswerConfirmation,
                    in: modelContext.container
                )
            } catch {
                readerWindowError = "保存作答状态失败：\(error.localizedDescription)"
            }
        }
    }

    private func setAnswerConfirmationEnabled(_ enabled: Bool) {
        guard !doodleSession.isPresented else { return }
        requiresAnswerConfirmation = enabled
        if !enabled {
            Task {
                do {
                    try await answerStateStore.markAllSelectedRevealed(in: modelContext.container)
                } catch {
                    readerWindowError = "更新答案确认状态失败：\(error.localizedDescription)"
                }
            }
        }
    }

    private func confirmAnswer(for questionID: String) {
        guard !doodleSession.isPresented,
              selectedAnswerOption(for: questionID) != nil,
              let item = itemsByID[questionID] else { return }
        Task {
            do {
                try await answerStateStore.setRevealed(
                    true,
                    for: questionID,
                    paperID: item.record.paperID,
                    questionID: item.question.id,
                    in: modelContext.container
                )
            } catch {
                readerWindowError = "确认答案失败：\(error.localizedDescription)"
            }
        }
    }

    private func setMissingAnswer(_ answer: String, for item: QuestionBankHomeQuestion) {
        do {
            try QuestionBankRepository.setMissingAnswer(
                paperID: item.record.paperID,
                questionID: item.question.id,
                answer: answer,
                context: modelContext
            )
            missingAnswerEditConfirmation = "答案已补录为 \(answer)。"
        } catch {
            missingAnswerEditError = error.localizedDescription
            missingAnswerEditConfirmation = nil
        }
    }

    private func assetRecord(for id: String, paperID: String) -> QuestionBankAssetReference? {
        guard !id.isEmpty else { return nil }
        return readerWindowStore.asset(paperID: paperID, assetID: id)
    }

    private func presentDoodle(for item: QuestionBankHomeQuestion) {
        let recordID = QuestionBankDoodleRepository.recordID(
            paperID: item.record.paperID, scope: .question(item.question.id)
        )
        guard !doodleSession.isPresented else { return }
        continuousQuestionDoodleRecordID = presentationMode == .continuous ? recordID : nil
        let readStart = ProcessInfo.processInfo.systemUptime
        let loadState = QuestionBankDoodleMemoryCache.shared.state(for: recordID)
        let cached = loadState.drawingData
        if loadState != .unknown { LibraryPerformanceLog.mark("doodle.read.cache-hit", since: readStart) }
        doodleSession.present(
            targetRecordID: recordID,
            drawingData: cached ?? "",
            legacyPreviewDataURL: "",
            isLoadingDrawing: loadState == .unknown,
            source: "question-bank-cross-paper",
            onSave: { drawingData, _, generation, revision in
                QuestionBankDoodleRepository.enqueueSave(
                    recordID: recordID,
                    drawingData: drawingData,
                    container: modelContext.container,
                    presentationGeneration: generation,
                    drawingRevision: revision,
                    debounceMilliseconds: 0
                ) { error in
                    guard doodleSession.presentationGeneration == generation,
                          doodleSession.targetRecordID == recordID else { return }
                    doodleSession.saveError = error
                    if error == nil { QuestionBankDoodleMemoryCache.shared.store(drawingData, for: recordID) }
                }
                return nil
            }
        )
        LibraryPerformanceLog.mark("doodle.tap-to-feedback", since: readStart)
        guard loadState == .unknown else { return }
        let container = modelContext.container
        doodleSession.beginDrawingLoad(recordID: recordID, startedAt: readStart) {
            try await QuestionBankDoodleRepository.drawingData(
                    recordID: recordID,
                    container: container
            )
        } onLoaded: { drawing in
            QuestionBankDoodleMemoryCache.shared.store(drawing, for: recordID)
        }
    }
}

private struct QuestionBankQuestionOverviewSheet: View {
    private enum Presentation: String, CaseIterable, Identifiable, Hashable {
        case numbers
        case cards
        var id: String { rawValue }
        var title: String { self == .numbers ? "题号" : "卡片" }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var presentation = Presentation.numbers
    @State private var answerStatesByID: [String: QuestionBankAnswerStateValue] = [:]

    let items: [QuestionBankReadingItem]
    let currentQuestionID: String?
    let container: ModelContainer
    let assetLookup: (String) -> QuestionBankAssetReference?
    let onSelect: (QuestionBankReadingItem) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                Picker("总览方式", selection: $presentation) {
                    ForEach(Presentation.allCases) { option in
                        Text(option.title).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .accessibilityIdentifier("question-bank-overview-presentation")

                if presentation == .numbers {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            ForEach(overviewGroups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    groupHeading(group)
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44), spacing: 7)], spacing: 7) {
                                        ForEach(group.questions) { candidate in
                                            if let item = itemsByID[candidate.id] { numberButton(item) }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(overviewGroups) { group in
                                groupHeading(group)
                                ForEach(group.questions) { candidate in
                                    if let item = itemsByID[candidate.id] { cardButton(item) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.white)
            .navigationTitle("题目总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .task(id: items.map(\.record.compoundID).joined(separator: "|")) {
            await loadAnswerStates(for: items.map { $0.record.compoundID })
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankAnswerStateRepository.changeNotification)) { notification in
            if notification.userInfo?[QuestionBankAnswerStateRepository.resetKey] as? Bool == true {
                answerStatesByID.removeAll()
                return
            }
            let changedIDs = notification.userInfo?[QuestionBankAnswerStateRepository.changedIDsKey] as? [String] ?? []
            let visibleIDs = Set(items.map { $0.record.compoundID })
            let affectedIDs = changedIDs.filter { visibleIDs.contains($0) }
            guard !affectedIDs.isEmpty else { return }
            if notification.userInfo?[QuestionBankAnswerStateRepository.clearedKey] as? Bool == true {
                for id in affectedIDs { answerStatesByID.removeValue(forKey: id) }
                return
            }
            Task { await loadAnswerStates(for: affectedIDs) }
        }
    }

    private var itemsByID: [String: QuestionBankReadingItem] {
        Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var overviewGroups: [QuestionBankOverviewGroup] {
        QuestionBankOverviewGrouping.groups(from: items.map { item in
            QuestionBankOverviewCandidate(
                id: item.id,
                paperID: item.record.paperID,
                paperTitle: item.record.title ?? "",
                questionNumber: displayNumber(for: item),
                moduleID: item.question.moduleID,
                moduleTitle: item.moduleTitle ?? "",
                moduleSequence: item.moduleSequence,
                type: item.question.type,
                subject: item.question.subject
            )
        })
    }

    private func displayNumber(for item: QuestionBankReadingItem) -> Int {
        QuestionBankDisplayNumber.resolve(
            originalNumber: item.question.number,
            localOrdinal: item.localOrdinal,
            usesLocalOrdinal: true
        )
    }

    private func answerStatus(for item: QuestionBankReadingItem) -> QuestionBankOverviewAnswerStatus {
        QuestionBankOverviewAnswerStatus.resolve(
            selectedOptionID: answerStatesByID[item.record.compoundID]?.selectedOptionID,
            answer: item.question.answer,
            isConfirmed: answerStatesByID[item.record.compoundID]?.isRevealed == true
        )
    }

    private func loadAnswerStates(for ids: [String]) async {
        do {
            let values = try await QuestionBankAnswerStateRepository.read(compoundIDs: ids, from: container)
            answerStatesByID.merge(values) { _, newest in newest }
            for id in ids where values[id] == nil { answerStatesByID.removeValue(forKey: id) }
        } catch {
            // The overview is read-only; the main reader surfaces persistence failures.
        }
    }

    private func groupHeading(_ group: QuestionBankOverviewGroup) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if group.startsModule {
                Text(group.moduleTitle)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
            }
            if let type = group.coarseQuestionType {
                Text(type)
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("question-bank-overview-group-\(group.id)")
    }

    private func numberButton(_ item: QuestionBankReadingItem) -> some View {
        let isCurrent = item.id == currentQuestionID
        return Button {
            onSelect(item)
            dismiss()
        } label: {
            QuestionBankNumberStatusCircle(
                number: displayNumber(for: item),
                status: answerStatus(for: item),
                isCurrent: isCurrent,
                diameter: 36
            )
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(false)
        .accessibilityLabel("第\(String(displayNumber(for: item)))题")
        .accessibilityValue(answerStatus(for: item).accessibilityValue)
        .accessibilityIdentifier("question-bank-number-card-\(item.id)")
    }

    private func cardButton(_ item: QuestionBankReadingItem) -> some View {
        let overview = item.overviewItem
        let isCurrent = item.id == currentQuestionID
        let headingDescription = overview.type.isEmpty ? "" : "，\(overview.type)"
        return Button {
            onSelect(item)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    QuestionBankNumberStatusCircle(
                        number: displayNumber(for: item),
                        status: answerStatus(for: item),
                        isCurrent: isCurrent,
                        diameter: 32
                    )
                    if !overview.type.isEmpty {
                        Text(overview.type)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if isCurrent {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                }
            }
            if let materialGroupLabel = overview.materialGroupLabel {
                Text(materialGroupLabel)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
            if !overview.stem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(verbatim: overview.stem)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            } else if let asset = assetLookup(overview.stemImageAssetID) {
                QuestionBankLocalImage(asset: asset, sizing: .overview)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .accessibilityLabel("第\(String(displayNumber(for: item)))题\(headingDescription)")
        .accessibilityValue(answerStatus(for: item).accessibilityValue)
        .accessibilityIdentifier("question-bank-overview-item-\(item.id)")
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(isCurrent ? AppTheme.accent.opacity(0.75) : Color(uiColor: .separator).opacity(0.4))
                .frame(height: isCurrent ? 1.5 : 0.7)
        }
    }
}

private struct QuestionBankMaterialBody: View {
    let material: QuestionBankMaterial
    let imageAsset: QuestionBankAssetReference?
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeading {
                HStack(spacing: 8) {
                    Text("共用材料").font(AppTheme.sectionTitleFont)
                    if !material.type.isEmpty {
                        Text(material.type).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
            }
            if !material.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(material.text)
                    .font(QuestionBankTypography.contentFont)
                    .lineSpacing(QuestionBankTypography.contentLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let imageAsset {
                QuestionBankLocalImage(asset: imageAsset, sizing: .material)
            }
            if material.text.isEmpty && material.imageAssetID.isEmpty {
                Text("本材料暂无可显示内容")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuestionBankQuestionDetailPanel<Content: View>: View {
    let question: QuestionBankQuestion
    let title: String
    let isDoodlePresented: Bool
    let onDone: () -> Void
    let onClearAnswer: () -> Void
    let onSave: (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    private let content: Content
    @State private var showsTextEditor = false
    @State private var showsClearAnswerConfirmation = false

    init(
        question: QuestionBankQuestion,
        title: String,
        isDoodlePresented: Bool,
        onDone: @escaping () -> Void,
        onClearAnswer: @escaping () -> Void,
        onSave: @escaping (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.question = question
        self.title = title
        self.isDoodlePresented = isDoodlePresented
        self.onDone = onDone
        self.onClearAnswer = onClearAnswer
        self.onSave = onSave
        self.content = content()
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("编辑题目") { showsTextEditor = true }
                            .accessibilityIdentifier("question-bank-edit-question")
                            .disabled(isDoodlePresented)
                    }
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        Menu {
                            Button("清除本题作答记录", role: .destructive) {
                                showsClearAnswerConfirmation = true
                            }
                            .accessibilityIdentifier("question-bank-clear-question-answer")
                        } label: {
                            Image(systemName: "ellipsis")
                        }
                        .accessibilityLabel("题目操作")
                        .accessibilityIdentifier("question-bank-question-actions")
                        .disabled(isDoodlePresented)
                        Button("完成", action: onDone)
                    }
                }
                .sheet(isPresented: $showsTextEditor) {
                    QuestionBankQuestionTextEditor(question: question, onSave: onSave)
                }
                .confirmationDialog(
                    "清除本题作答记录？",
                    isPresented: $showsClearAnswerConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("清除本题作答记录", role: .destructive, action: onClearAnswer)
                    Button("取消", role: .cancel) { }
                } message: {
                    Text("将清除本题已选选项和答案揭示状态，涂鸦及题目文字修改会保留。")
                }
        }
        .presentationDetents([.large])
    }
}

private struct QuestionBankQuestionTextEditor: View {
    @Environment(\.dismiss) private var dismiss
    let question: QuestionBankQuestion
    let onSave: (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    @State private var stem: String
    @State private var optionTexts: [String: String]
    @State private var isDifficult: Bool
    @State private var needsReview: Bool
    @State private var knowledgePointsText: String
    @State private var weaknessTagsText: String
    @State private var saveError: String?

    init(
        question: QuestionBankQuestion,
        onSave: @escaping (String, [String: String], QuestionBankQuestionAnnotations) throws -> Void
    ) {
        self.question = question
        self.onSave = onSave
        _stem = State(initialValue: question.stem)
        let annotations = QuestionBankQuestionAnnotations(question: question)
        _isDifficult = State(initialValue: annotations.isDifficult)
        _needsReview = State(initialValue: annotations.needsReview)
        _knowledgePointsText = State(initialValue: annotations.knowledgePoints.joined(separator: "、"))
        _weaknessTagsText = State(initialValue: annotations.weaknessTags.joined(separator: "、"))
        _optionTexts = State(initialValue: Dictionary(
            question.options.map { ($0.id, $0.text) },
            uniquingKeysWith: { first, _ in first }
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("题干") {
                    TextEditor(text: $stem)
                        .frame(minHeight: 150)
                        .accessibilityIdentifier("question-bank-edit-stem")
                }
                Section {
                    ForEach(question.options) { option in
                        HStack(alignment: .top, spacing: 8) {
                            Text(option.id)
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 32, height: 28)
                                .background(AppTheme.accent.opacity(0.10), in: Capsule())
                            TextField("", text: optionBinding(for: option.id), axis: .vertical)
                                .lineLimit(1...3)
                                .font(QuestionBankTypography.contentFont)
                                .lineSpacing(QuestionBankTypography.contentLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.vertical, 1)
                                .accessibilityLabel("选项 \(option.id)")
                                .accessibilityIdentifier("question-bank-edit-option-\(option.id)")
                        }
                        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
                        .accessibilityElement(children: .contain)
                    }
                }
                Section("标记与知识点") {
                    Toggle("难题", isOn: $isDifficult)
                        .accessibilityIdentifier("question-bank-edit-difficult")
                    Toggle("待复习", isOn: $needsReview)
                        .accessibilityIdentifier("question-bank-edit-needs-review")
                    TextField("知识点，用顿号分隔", text: $knowledgePointsText)
                        .accessibilityIdentifier("question-bank-edit-knowledge-points")
                    TextField("弱项标签，用顿号分隔", text: $weaknessTagsText)
                        .accessibilityIdentifier("question-bank-edit-weakness-tags")
                }
            }
            .listSectionSpacing(8)
            .navigationTitle("编辑题目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .accessibilityIdentifier("question-bank-save-question-text")
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func optionBinding(for optionID: String) -> Binding<String> {
        Binding(
            get: { optionTexts[optionID] ?? "" },
            set: { optionTexts[optionID] = $0 }
        )
    }

    private func save() {
        do {
            let originalOptionTexts = Dictionary(
                question.options.map { ($0.id, $0.text) },
                uniquingKeysWith: { first, _ in first }
            )
            let editedOptionTexts = optionTexts.filter { originalOptionTexts[$0.key] != $0.value }
            try onSave(
                stem,
                editedOptionTexts,
                QuestionBankQuestionAnnotations(
                    isDifficult: isDifficult,
                    needsReview: needsReview,
                    knowledgePoints: QuestionBankQuestionAnnotations.tags(from: knowledgePointsText),
                    weaknessTags: QuestionBankQuestionAnnotations.tags(from: weaknessTagsText)
                )
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }
}

private struct QuestionBankReaderOptionsPopover: View {
    private struct Choice: Identifiable {
        let title: String
        let accessibilityLabel: String
        var id: String { title }
    }

    @Binding var presentationMode: QuestionBankPresentationMode
    @Binding var readingMode: QuestionBankReadingMode
    @Binding var requiresAnswerConfirmation: Bool
    let currentQuestionTitle: String?
    let onClearCurrentQuestion: () -> Void
    let onDismiss: () -> Void
    @State private var showsClearAnswerConfirmation = false

    var body: some View {
        VStack(spacing: 10) {
            choiceRow(
                label: "浏览",
                selected: presentationMode.shortTitle,
                options: [
                    Choice(title: "连续", accessibilityLabel: "连续阅读"),
                    Choice(title: "单题", accessibilityLabel: "单题模式")
                ],
                identifierPrefix: "question-bank-presentation"
            ) { value in
                presentationMode = value == "连续" ? .continuous : .single
            }
            choiceRow(
                label: "答题",
                selected: readingMode.title,
                options: [
                    Choice(title: "刷题", accessibilityLabel: "刷题"),
                    Choice(title: "看题", accessibilityLabel: "看题")
                ],
                identifierPrefix: "question-bank-reading-mode"
            ) { value in
                readingMode = value == "刷题" ? .practice : .reading
            }
            Toggle(isOn: $requiresAnswerConfirmation) {
                Text("确认")
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                    .frame(width: 44, alignment: .leading)
            }
            .toggleStyle(QuestionBankConfirmationCapsuleToggleStyle())
            .accessibilityLabel("选择后确认答案")
            .accessibilityValue(requiresAnswerConfirmation ? "开启" : "关闭")
            .accessibilityIdentifier("question-bank-confirm-answer-toggle")
            Text("设置会立即应用到当前题目。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Button(role: .destructive) {
                showsClearAnswerConfirmation = true
            } label: {
                Label(
                    currentQuestionTitle.map { "清除\($0)作答记录" } ?? "清除本题作答记录",
                    systemImage: "arrow.counterclockwise"
                )
                .font(AppTheme.auxiliaryFont)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(currentQuestionTitle == nil)
            .accessibilityIdentifier("question-bank-clear-current-answer")
        }
        .padding(12)
        .frame(width: 248)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .confirmationDialog(
            "清除本题作答记录？",
            isPresented: $showsClearAnswerConfirmation,
            titleVisibility: .visible
        ) {
            Button("清除本题作答记录", role: .destructive) {
                onClearCurrentQuestion()
                onDismiss()
            }
            Button("取消", role: .cancel) { }
        } message: {
            Text("只清除当前题已选选项和答案揭示状态；题目、笔记、涂鸦及编辑内容会保留。")
        }
    }

    private func choiceRow(
        label: String,
        selected: String,
        options: [Choice],
        identifierPrefix: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 3) {
                ForEach(options) { option in
                    Button {
                        onSelect(option.title)
                        onDismiss()
                    } label: {
                        Text(option.title)
                            .font(AppTheme.auxiliaryFont.weight(.medium))
                            .foregroundStyle(selected == option.title ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(selected == option.title ? AppTheme.accent : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.accessibilityLabel)
                    .accessibilityValue(selected == option.title ? "已选" : "")
                    .accessibilityAddTraits(selected == option.title ? .isSelected : [])
                    .accessibilityIdentifier("\(identifierPrefix)-\(option.title)")
                }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
        }
        .frame(height: 38)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(label)方式")
    }
}

private struct QuestionBankProvenanceDisclosure: View {
    let title: String
    let entries: [QuestionBankProvenance]
    var sourcePapers: [QuestionBankSourcePaper] = []

    var body: some View {
        if !entries.isEmpty {
            DisclosureGroup(title) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        VStack(alignment: .leading, spacing: 3) {
                            Text("来源 \(index + 1)")
                                .font(AppTheme.auxiliaryFont.weight(.semibold))
                            Text(detail(for: entry, sourcePapers: sourcePapers))
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if let evidence = entry.evidence, !evidence.isEmpty {
                                Text(evidence)
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let source = sourcePapers.first(where: { $0.id == entry.sourcePaperID }) {
                                if let sha256 = source.originalFileSHA256, !sha256.isEmpty {
                                    Text("SHA-256：\(sha256)")
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 7)
            }
            .font(AppTheme.auxiliaryFont.weight(.medium))
            .accessibilityIdentifier("question-bank-provenance-disclosure-\(title)")
        }
    }

    private func detail(
        for entry: QuestionBankProvenance,
        sourcePapers: [QuestionBankSourcePaper]
    ) -> String {
        let source = sourcePapers.first(where: { $0.id == entry.sourcePaperID })
        let fileName = QuestionBankSourceDisplay.cleanedFileName(source?.originalFileName ?? "")
        var parts = [fileName.isEmpty ? "来源卷 \(entry.sourcePaperID)" : fileName]
        if let province = entry.provinceName ?? entry.provinceCode, !province.isEmpty {
            parts.append(province)
        }
        if let number = entry.sourceQuestionNumber { parts.append("原第\(number)题") }
        if let numbers = entry.sourceQuestionNumbers, !numbers.isEmpty {
            parts.append("原题号 \(numbers.map(String.init).joined(separator: "、"))")
        }
        if let page = entry.originalPage, !page.isEmpty { parts.append("第\(page)页") }
        return parts.joined(separator: " · ")
    }
}

private struct QuestionBankConfirmationCapsuleToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 8) {
            configuration.label
            HStack(spacing: 3) {
                capsule("关闭", isSelected: !configuration.isOn,
                        accessibilityIdentifier: "question-bank-confirm-answer-off") {
                    configuration.isOn = false
                }
                capsule("开启", isSelected: configuration.isOn,
                        accessibilityIdentifier: "question-bank-confirm-answer-on") {
                    configuration.isOn = true
                }
            }
            .padding(3)
            .background(Color(uiColor: .tertiarySystemGroupedBackground), in: Capsule())
            .frame(maxWidth: .infinity)
        }
        .frame(height: 38)
        .contentShape(Rectangle())
    }

    private func capsule(
        _ title: String,
        isSelected: Bool,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(AppTheme.auxiliaryFont.weight(.medium))
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .frame(maxWidth: .infinity, minHeight: 32)
                .background(isSelected ? AppTheme.accent : Color.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(isSelected ? "已选" : "")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}

private struct QuestionBankMissingAnswerMenu: View {
    let questionID: String
    let options: [QuestionBankOption]
    let onSelect: (String) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("正确答案尚未录入")
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Menu {
                ForEach(options) { option in
                    Button("设为 \(option.id)") { onSelect(option.id) }
                }
            } label: {
                Label("补录答案", systemImage: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
            .accessibilityIdentifier("question-bank-missing-answer-\(questionID)")
        }
        .font(QuestionBankTypography.contentFont)
        .accessibilityElement(children: .contain)
    }
}

private struct QuestionBankOptionRow: View {
    @ScaledMetric(relativeTo: .body) private var markerDiameter: CGFloat = 26

    let questionID: String
    let option: QuestionBankOption
    let answer: String
    let readingMode: QuestionBankReadingMode
    let selectedOptionID: String?
    let revealsAnswer: Bool
    let isSelectionLocked: Bool
    let isInteractionBlocked: Bool
    var showsGraphLayout = false
    let onSelect: () -> Void
    let assetLookup: (String) -> QuestionBankAssetReference?

    var body: some View {
        if readingMode == .practice {
            Button {
                guard !isInteractionBlocked else { return }
                onSelect()
            } label: {
                row
            }
            .buttonStyle(QuestionBankOptionButtonStyle())
            // The first choice remains locked semantically, while the custom
            // style keeps that state from dimming the option text and marker.
            .accessibilityValue(optionAccessibilityValue)
            .accessibilityHint(isSelectionLocked ? "答案已提交，不能更改选择" : "选择此选项")
            .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
            .disabled(isSelectionLocked)
        } else {
            row
                .accessibilityValue(optionAccessibilityValue)
                .accessibilityIdentifier("question-bank-option-\(questionID)-\(option.id)")
        }
    }

    private var row: some View {
        let displayText = QuestionBankOptionDisplay.text(for: option)
        return HStack(
            alignment: QuestionBankOptionRowLayout.verticalAlignment(hasText: displayText != nil),
            spacing: 7
        ) {
            QuestionBankOptionMarker(
                letter: option.id,
                state: markerState,
                diameter: markerDiameter,
                font: QuestionBankTypography.contentFont
            )
            VStack(alignment: .leading, spacing: 8) {
                if let displayText {
                    Text(displayText)
                        .font(QuestionBankTypography.contentFont)
                        .foregroundStyle(Color.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !option.imageAssetID.isEmpty, let asset = assetLookup(option.imageAssetID) {
                    QuestionBankLocalImage(asset: asset, sizing: showsGraphLayout ? .graph : .option)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.firstTextBaseline) { dimensions in
                dimensions[.firstTextBaseline]
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(height: 0.7)
        }
    }

    private var markerState: QuestionBankOptionMarkerState {
        guard showsKnownAnswer else { return isSelected ? .selected : .unselected }
        if answer == option.id { return .correct }
        return isSelected ? .incorrect : .unselected
    }

    private var showsKnownAnswer: Bool {
        revealsAnswer && !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var optionAccessibilityValue: String {
        guard showsKnownAnswer else { return isSelected ? "已选择" : "未选择" }
        if answer == option.id { return isSelected ? "已选择，回答正确" : "正确答案" }
        if isSelected { return "已选择，回答错误" }
        return "未选择，非正确答案"
    }

    private var isSelected: Bool {
        readingMode == .practice && selectedOptionID == option.id
    }

}

private struct QuestionBankOptionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed && isEnabled ? 0.82 : 1)
    }
}

private struct QuestionBankQuestionAnnotationBadges: View {
    let question: QuestionBankQuestion

    private var labels: [String] {
        (question.isDifficult == true ? ["难题"] : [])
            + (question.needsReview == true ? ["待复习"] : [])
            + (question.knowledgePoints ?? [])
            + (question.weaknessTags ?? [])
    }

    private var hasAnnotations: Bool {
        question.isDifficult == true || question.needsReview == true
            || !(question.knowledgePoints ?? []).isEmpty || !(question.weaknessTags ?? []).isEmpty
    }

    var body: some View {
        if hasAnnotations {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    if question.isDifficult == true { badge("难题", color: AppTheme.danger) }
                    if question.needsReview == true { badge("待复习", color: AppTheme.accent) }
                    ForEach(question.knowledgePoints ?? [], id: \.self) { value in
                        badge(value, color: AppTheme.success)
                    }
                    ForEach(question.weaknessTags ?? [], id: \.self) { value in
                        badge(value, color: AppTheme.accent)
                    }
                }
                .padding(.bottom, 8)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("题目标记：\(labels.joined(separator: "、"))")
        }
    }

    private func badge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.09), in: Capsule())
    }
}

private struct QuestionBankAnswerFollowUpAction: View {
    @Environment(\.modelContext) private var modelContext

    let analysis: QuestionBankQuestionAnalysisContext
    var categoryOverride: QuestionBankErrorBookCategory? = nil

    @State private var isSaving = false
    @State private var linkResolution: QuestionBankErrorBookLinkResolution?
    @State private var linkLookupError: String?
    @State private var linkLookupGeneration = 0
    @State private var errorMessage = ""

    private var question: QuestionBankQuestion { analysis.question }
    private var category: QuestionBankErrorBookCategory {
        categoryOverride ?? (analysis.selectedOptionID == question.answer ? .uncertain : .wrong)
    }

    private var linkLookupID: String {
        let linkedIDs = (question.linkedErrorRecordIDs ?? []).sorted().joined(separator: ",")
        return "\(question.paperID)|\(question.id)|\(linkedIDs)|\(linkLookupGeneration)"
    }

    private var buttonTitle: String {
        if let linkLookupError { return linkLookupError.isEmpty ? "重试检查" : "重试检查错题本" }
        switch linkResolution?.state {
        case .some(.linked): return "已加入错题本"
        case .some(.identityConflict): return "错题记录标识冲突"
        case .some(.unlinked):
            switch category {
            case .wrong: return "加入错题本"
            case .uncertain: return "加入不确定题"
            case .cannotSolve: return "标记不会做"
            }
        case .none: return "正在检查错题记录…"
        }
    }

    private var buttonIcon: String {
        if linkLookupError != nil { return "arrow.clockwise" }
        switch linkResolution?.state {
        case .some(.linked): return "checkmark.circle.fill"
        case .some(.identityConflict): return "exclamationmark.triangle"
        case .some(.unlinked): return "plus.circle"
        case .none: return "hourglass"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                if linkLookupError != nil {
                    retryLinkLookup()
                } else {
                    addToErrorBook()
                }
            } label: {
                Label(buttonTitle, systemImage: buttonIcon)
                    .font(AppTheme.auxiliaryFont.weight(.medium))
            }
            .buttonStyle(.bordered)
            .disabled(isSaving || (linkLookupError == nil && linkResolution?.state != .unlinked))
            .accessibilityIdentifier("question-bank-error-book-action-\(question.id)")

            if let state = linkResolution?.state, case .identityConflict = state {
                Text("已有错题记录使用了这道题的标识；为避免重复或误关联，未新增记录。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.danger)
            }
            if let linkLookupError {
                Text("错题关联状态读取失败：\(linkLookupError)")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.danger)
            }
            if !errorMessage.isEmpty {
                Text(errorMessage)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.danger)
                    .accessibilityIdentifier("question-bank-error-book-error-\(question.id)")
            }
        }
        .task(id: linkLookupID) {
            linkResolution = nil
            linkLookupError = nil
            let question = analysis.question
            let container = modelContext.container
            do {
                let resolution = try await QuestionBankErrorBookLinkIndex.shared.resolve(
                    question: question,
                    container: container
                )
                guard !Task.isCancelled else { return }
                linkResolution = resolution
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                linkLookupError = error.localizedDescription
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: QuestionBankRecordChangeSignal.notification)) { notification in
            guard QuestionBankRecordChangeSignal.affects(question.paperID, notification: notification) else { return }
            let changes = QuestionBankRecordChangeSignal.recordChanges(
                for: question.paperID,
                notification: notification
            )
            let shouldInvalidate = changes == nil || changes?.contains(where: {
                $0.kind == .structure || ($0.kind == .questionLinks && $0.recordID == question.id)
            }) == true
            guard shouldInvalidate else { return }
            let paperID = question.paperID
            let questionID = question.id
            let container = modelContext.container
            Task { @MainActor in
                await QuestionBankErrorBookLinkIndex.shared.invalidateResolution(
                    paperID: paperID,
                    questionID: questionID,
                    container: container
                )
                linkLookupGeneration &+= 1
            }
        }
    }

    private func retryLinkLookup() {
        linkLookupError = nil
        linkLookupGeneration &+= 1
    }

    private func addToErrorBook() {
        guard !isSaving,
              let linkResolution,
              linkResolution.state == .unlinked else { return }
        isSaving = true
        errorMessage = ""
        defer { isSaving = false }
        do {
            let resolvedAnalysis: QuestionBankQuestionAnalysisContext
            if analysis.record.payload.isEmpty {
                let compoundID = analysis.record.compoundID
                var descriptor = FetchDescriptor<QuestionBankRecord>(
                    predicate: #Predicate { $0.compoundID == compoundID }
                )
                descriptor.fetchLimit = 1
                guard let record = try modelContext.fetch(descriptor).first else {
                    throw QuestionBankErrorBookAddFailure.missingQuestion
                }
                resolvedAnalysis = analysis.replacingRecord(record)
            } else {
                resolvedAnalysis = analysis
            }
            let question = resolvedAnalysis.currentQuestion
            switch try QuestionBankErrorBookRepository.add(
                analysis: resolvedAnalysis,
                question: question,
                category: category,
                candidateRecordIDs: linkResolution.candidateRecordIDs,
                context: modelContext
            ) {
            case .added(let recordID), .alreadyAdded(let recordID):
                self.linkResolution = QuestionBankErrorBookLinkResolution(
                    state: .linked(recordID: recordID),
                    candidateRecordIDs: Array(Set(linkResolution.candidateRecordIDs + [recordID])).sorted()
                )
            }
        } catch {
            errorMessage = "加入失败：\(error.localizedDescription)"
        }
    }
}

private enum QuestionBankImageLoadSource: Sendable {
    case memoryCache
    case backgroundDecode
    case joinedInFlight
}

private struct QuestionBankImageLoadResponse: @unchecked Sendable {
    let image: UIImage?
    let source: QuestionBankImageLoadSource
}

private struct QuestionBankImageRequest: Sendable {
    let cacheKey: String
    let url: URL
    let maximumPixelDimension: Int
    let scale: CGFloat
}

private final class QuestionBankDecodedImageBox: NSObject, @unchecked Sendable {
    let image: UIImage
    let byteCost: Int

    init(image: UIImage, byteCost: Int) {
        self.image = image
        self.byteCost = byteCost
    }
}

private final class QuestionBankImageDecodeCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private enum QuestionBankLocalImageDecoder {
    static func decode(
        request: QuestionBankImageRequest,
        cancellation: QuestionBankImageDecodeCancellation
    ) -> QuestionBankDecodedImageBox? {
        guard !cancellation.isCancelled,
              let data = try? Data(contentsOf: request.url, options: [.mappedIfSafe]),
              !cancellation.isCancelled,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: request.maximumPixelDimension,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard !cancellation.isCancelled,
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !cancellation.isCancelled else { return nil }
        let image = UIImage(cgImage: thumbnail, scale: request.scale, orientation: .up)
        return QuestionBankDecodedImageBox(
            image: image,
            byteCost: thumbnail.bytesPerRow * thumbnail.height
        )
    }
}

private actor QuestionBankImageDecodeService {
    static let shared = QuestionBankImageDecodeService()

    private struct InFlight {
        let id: UUID
        let task: Task<QuestionBankDecodedImageBox?, Never>
        var subscribers: Set<UUID>
    }

    private let cache = NSCache<NSString, QuestionBankDecodedImageBox>()
    private let decodingQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "com.baoger07122.kaogongreview.question-bank-image-decode"
        queue.qualityOfService = .userInitiated
        queue.maxConcurrentOperationCount = 2
        queue.underlyingQueue = DispatchQueue(label: "com.baoger07122.kaogongreview.question-bank-image-workers", attributes: .concurrent)
        return queue
    }()
    private var inFlight: [String: InFlight] = [:]

    private init() {
        cache.totalCostLimit = 72 * 1_024 * 1_024
        cache.countLimit = 96
    }

    func image(
        for request: QuestionBankImageRequest,
        subscriberID: UUID
    ) async -> QuestionBankImageLoadResponse {
        await withTaskCancellationHandler {
            await resolve(request, subscriberID: subscriberID)
        } onCancel: {
            Task { await self.release(request.cacheKey, subscriberID: subscriberID) }
        }
    }

    private func resolve(
        _ request: QuestionBankImageRequest,
        subscriberID: UUID
    ) async -> QuestionBankImageLoadResponse {
        let cacheKey = request.cacheKey as NSString
        if let cached = cache.object(forKey: cacheKey) {
            return QuestionBankImageLoadResponse(image: cached.image, source: .memoryCache)
        }

        let workerID: UUID
        let task: Task<QuestionBankDecodedImageBox?, Never>
        let source: QuestionBankImageLoadSource
        if var worker = inFlight[request.cacheKey], !worker.task.isCancelled {
            worker.subscribers.insert(subscriberID)
            inFlight[request.cacheKey] = worker
            workerID = worker.id
            task = worker.task
            source = .joinedInFlight
        } else {
            workerID = UUID()
            let cancellation = QuestionBankImageDecodeCancellation()
            let queue = decodingQueue
            task = Task.detached(priority: .userInitiated) {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { (continuation: CheckedContinuation<QuestionBankDecodedImageBox?, Never>) in
                        queue.addOperation {
                            continuation.resume(returning: QuestionBankLocalImageDecoder.decode(
                                request: request,
                                cancellation: cancellation
                            ))
                        }
                    }
                } onCancel: {
                    cancellation.cancel()
                }
            }
            inFlight[request.cacheKey] = InFlight(id: workerID, task: task, subscribers: [subscriberID])
            source = .backgroundDecode
        }

        let decoded = await task.value
        if let worker = inFlight[request.cacheKey], worker.id == workerID {
            inFlight[request.cacheKey] = nil
            if !worker.subscribers.isEmpty, let decoded {
                cache.setObject(decoded, forKey: cacheKey, cost: decoded.byteCost)
            }
        }
        return QuestionBankImageLoadResponse(image: decoded?.image, source: source)
    }

    private func release(_ cacheKey: String, subscriberID: UUID) {
        guard var worker = inFlight[cacheKey], worker.subscribers.remove(subscriberID) != nil else { return }
        inFlight[cacheKey] = worker
        if worker.subscribers.isEmpty {
            worker.task.cancel()
        }
    }
}

struct QuestionBankLocalImage: View {
    enum Sizing: String {
        case material
        case stem
        case option
        case graph
        case overview
    }

    let asset: QuestionBankAssetReference
    var sizing: Sizing = .material
    var activationTab: RootTab = .questionBank

    @Environment(\.displayScale) private var displayScale
    @Environment(\.rootTabSelection) private var rootTabSelection
    @State private var image: UIImage?
    @State private var failedToLoad = false

    private var maximumPixelDimension: Int {
        let scale = max(1, displayScale)
        let targetPoints: CGFloat
        let hardLimit: Int
        switch sizing {
        case .material, .stem:
            targetPoints = 1_500
            hardLimit = 3_072
        case .option:
            targetPoints = 450
            hardLimit = 900
        case .graph:
            targetPoints = 1_900
            hardLimit = 4_096
        case .overview:
            targetPoints = 210
            hardLimit = 420
        }
        return min(hardLimit, max(1, Int((targetPoints * scale).rounded(.up))))
    }

    private var requestKey: String {
        [
            asset.compoundID,
            asset.assetRelativePath ?? "",
            String(asset.contentRevision),
            sizing.rawValue,
            String(Int(displayScale * 100)),
            String(maximumPixelDimension)
        ].joined(separator: "|")
    }

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else if failedToLoad {
                Label("图片无法读取", systemImage: "exclamationmark.triangle")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                    .fill(AppTheme.secondaryBackground)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 72)
            }
        }
        .task(id: "\(requestKey)|\(rootTabSelection.wrappedValue.rawValue)|\(activationTab.rawValue)") {
            image = nil
            failedToLoad = false
            guard rootTabSelection.wrappedValue == activationTab else { return }
            guard let url = QuestionBankAssetStore.url(for: asset.assetRelativePath) else {
                failedToLoad = true
                return
            }
            let identity = requestKey
            let started = ProcessInfo.processInfo.systemUptime
            let response = await QuestionBankImageDecodeService.shared.image(
                for: QuestionBankImageRequest(
                    cacheKey: identity,
                    url: url,
                    maximumPixelDimension: maximumPixelDimension,
                    scale: max(1, displayScale)
                ),
                subscriberID: UUID()
            )
            guard !Task.isCancelled, requestKey == identity else { return }
            switch response.source {
            case .memoryCache:
                NativePerformanceLog.event("question-bank image cache hit")
            case .backgroundDecode:
                NativePerformanceLog.mark("question-bank image background decode pixels=\(maximumPixelDimension)", since: started)
            case .joinedInFlight:
                NativePerformanceLog.event("question-bank image joined in-flight decode")
            }
            image = response.image
            failedToLoad = response.image == nil
        }
    }


    @ViewBuilder
    private func imageView(_ image: UIImage) -> some View {
        switch sizing {
        case .material, .stem:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .option:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 126, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .graph:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .overview:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 150, maxHeight: 86, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

}

extension QuestionBankRecord {
    func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
        try? JSONDecoder().decode(type, from: payload)
    }
}
