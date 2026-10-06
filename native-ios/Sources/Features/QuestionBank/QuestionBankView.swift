import SwiftUI
import SwiftData
import OSLog

private enum QuestionBankImportSheet: Identifiable {
    case picker(UUID)
    case preparing(UUID)
    case preview(QuestionBankImportPlan)

    var id: String {
        // Keep one sheet owner across picker → preparation → preview. Replacing
        // the item ID while a document picker is dismissing can drop the preview.
        "question-bank-import-flow"
    }
}

@MainActor
private final class QuestionBankImportProgressModel: ObservableObject {
    @Published private(set) var message: String?
    private var activeRunID: UUID?
    private var fileName = ""

    func setMessage(_ value: String?) {
        message = value
    }

    func begin(runID: UUID, fileName: String) {
        activeRunID = runID
        self.fileName = fileName
        message = "\(fileName)／准备读取"
    }

    func update(runID: UUID, phase: QuestionBankImportPhase) {
        guard activeRunID == runID else { return }
        message = "\(fileName)／\(phase.rawValue)"
    }

    func finish(runID: UUID, message: String? = nil) {
        guard activeRunID == runID else { return }
        activeRunID = nil
        fileName = ""
        self.message = message
    }
}

struct QuestionBankView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.rootTabSelection) private var rootTabSelection
    @EnvironmentObject private var importRouter: QuestionBankImportRouter
    @Query private var records: [QuestionBankRecord]
    @Query private var batchIndexes: [QuestionBankBatchRecord]
    @Query private var batchSources: [QuestionBankBatchSourceRecord]
    @Query private var batchMaterialLinks: [QuestionBankBatchMaterialLinkRecord]
    @Query private var batchQuestionLinks: [QuestionBankBatchQuestionLinkRecord]
    @StateObject private var importProgress = QuestionBankImportProgressModel()
    @StateObject private var importSelection = QuestionBankImportSelectionCoordinator()
    @State private var searchText = ""
    @State private var selectedYear = ""
    @State private var selectedExamType = ""
    @State private var selectedModuleTitle = ""
    @State private var questionNumber = ""
    @State private var activeImportSheet: QuestionBankImportSheet?
    @State private var isPreparingImport = false
    @State private var isCancellingImport = false
    @State private var isCommittingImport = false
    @State private var importStagingDirectory: URL?
    @State private var inlineImportFailure: String?
    @State private var showImportAlert = false
    @State private var importAlertTitle = "导入未完成"
    @State private var importAlertMessage = ""
    @State private var activeImportID: UUID?
    @State private var importWorkerID: UUID?
    @State private var importWorker: Task<QuestionBankImportPlan, Error>?

    private let importLogger = Logger(subsystem: "com.baoger07122.kaogongreview", category: "QuestionBankImportUI")

    private var paperRecords: [QuestionBankRecord] {
        records.filter { $0.kind == QuestionBankRepository.paperKind }
    }
    private var sortedBatches: [QuestionBankBatchRecord] {
        batchIndexes.sorted { ($0.year, $0.displayName) > ($1.year, $1.displayName) }
    }
    private var years: [String] {
        Array(Set(paperRecords.compactMap(\.year).map(String.init))).sorted(by: >)
    }
    private var examTypes: [String] {
        Array(Set(paperRecords.compactMap(\.examType))).sorted()
    }
    private var moduleTitles: [String] {
        Array(Set(records.filter { $0.kind == QuestionBankRepository.moduleKind }
            .compactMap { $0.decoded(QuestionBankModule.self)?.title })).sorted()
    }
    private var visiblePapers: [QuestionBankRecord] {
        paperRecords.filter { paper in
            guard let data = paper.decoded(QuestionBankPaper.self) else { return false }
            if !selectedYear.isEmpty && String(data.year) != selectedYear { return false }
            if !selectedExamType.isEmpty && data.examType != selectedExamType { return false }
            if !selectedModuleTitle.isEmpty {
                let containsModule = records.contains {
                    $0.paperID == paper.paperID && $0.kind == QuestionBankRepository.moduleKind
                        && $0.title == selectedModuleTitle
                }
                if !containsModule { return false }
            }
            if let number = Int(questionNumber), number > 0,
               !records.contains(where: {
                   $0.paperID == paper.paperID && $0.kind == QuestionBankRepository.questionKind
                       && $0.questionNumber == number
               }) { return false }
            if let number = Int(questionNumber), number > 0, !selectedModuleTitle.isEmpty {
                let selectedModuleIDs = Set(records.filter {
                    $0.paperID == paper.paperID && $0.kind == QuestionBankRepository.moduleKind
                        && $0.title == selectedModuleTitle
                }.map(\.stableID))
                if !records.contains(where: {
                    $0.paperID == paper.paperID && $0.kind == QuestionBankRepository.questionKind
                        && $0.questionNumber == number && selectedModuleIDs.contains($0.moduleID ?? "")
                }) { return false }
            }
            if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                let matchesPaper = paper.searchText.localizedCaseInsensitiveContains(query)
                let matchesRecord = records.contains {
                    $0.paperID == paper.paperID && $0.searchText.localizedCaseInsensitiveContains(query)
                }
                if !matchesPaper && !matchesRecord { return false }
            }
            return true
        }
        .sorted { left, right in
            if left.year != right.year { return (left.year ?? 0) > (right.year ?? 0) }
            return (left.title ?? "") < (right.title ?? "")
        }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let importStatusMessage = importProgress.message {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if isPreparingImport {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "info.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            Text(importStatusMessage)
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if isPreparingImport && !isCancellingImport {
                                Button("取消", action: cancelPreparingImport)
                                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if !sortedBatches.isEmpty {
                        VStack(alignment: .leading, spacing: 9) {
                            Text("跨卷批次").font(AppTheme.sectionTitleFont)
                            ForEach(sortedBatches, id: \.identityKey) { batch in
                                NavigationLink {
                                    QuestionBankBatchDetailView(batchID: batch.identityKey)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: "rectangle.stack.fill")
                                            .foregroundStyle(AppTheme.accent)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(batch.displayName).font(AppTheme.cardTitleFont).foregroundStyle(.primary)
                                            Text("\(batch.sourceCount) 个来源 · \(batch.uniqueQuestionCount) 道唯一题 · \(batch.pendingCount) 条待核")
                                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .nativeCard(padding: 13)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("question-bank-batch-\(batch.identityKey)")
                            }
                        }
                    }
                    filterControls

                    if visiblePapers.isEmpty {
                        NativeStatusCard(
                            title: paperRecords.isEmpty ? "还没有导入真题" : "没有符合条件的试卷",
                            detail: paperRecords.isEmpty
                                ? "优先导入单文件 JSON 真题包；旧版 ZIP 套卷也可继续使用。"
                                : "调整年份、考试类型、模块、题号或搜索关键词后重试。",
                            systemImage: "books.vertical",
                            color: AppTheme.accent
                        )
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(visiblePapers, id: \.compoundID) { record in
                                NavigationLink {
                                    paperDestination(for: record)
                                } label: {
                                    paperCard(record)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("question-bank-paper-\(record.stableID)")
                            }
                        }
                    }
                }
                .padding(20)
            }
            importButton
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("真题库")
        .navigationBarTitleDisplayMode(.inline)
        .rootTabBarContentInset()
        .sheet(item: $activeImportSheet, onDismiss: handleImportSheetDismissal) { sheet in
            switch sheet {
            case .picker(let requestID):
                QuestionBankDocumentPicker(
                    requestID: requestID,
                    onPick: handlePickedDocuments,
                    onCancel: handleDocumentPickerCancellation
                )
                .ignoresSafeArea()
            case .preparing:
                QuestionBankImportPreparingView(
                    message: importProgress.message ?? "正在准备读取…",
                    onCancel: cancelPreparingImport
                )
            case .preview(let plan):
                QuestionBankImportPreview(
                    plan: plan,
                    records: records,
                    batchSources: batchSources,
                    isImporting: isCommittingImport,
                    importFailure: $inlineImportFailure,
                    onImport: { decision, batchMetadata in commitImport(plan, decision: decision, batchMetadata: batchMetadata) },
                    onCancel: { activeImportSheet = nil }
                )
            }
        }
        .alert(importAlertTitle, isPresented: $showImportAlert) {
            Button("好", role: .cancel) { }
        } message: {
            Text(importAlertMessage)
        }
        .onAppear { NativePerformanceLog.event("question bank onAppear") }
        .onAppear(perform: processPendingExternalFileIfPossible)
        .onDisappear {
            if isPreparingImport { cancelPreparingImport() }
        }
        .onChange(of: importRouter.pendingRequestIDs) { _, _ in
            processPendingExternalFileIfPossible()
        }
        .onChange(of: rootTabSelection.wrappedValue) { _, selectedTab in
            if selectedTab == .questionBank { processPendingExternalFileIfPossible() }
        }
        .onChange(of: isPreparingImport) { _, isPreparing in
            if !isPreparing { processPendingExternalFileIfPossible() }
        }
        .onChange(of: isCommittingImport) { _, isCommitting in
            if !isCommitting { processPendingExternalFileIfPossible() }
        }
        .onChange(of: showImportAlert) { _, isShowing in
            if !isShowing { processPendingExternalFileIfPossible() }
        }
    }

    private var importButton: some View {
        Button {
            presentDocumentPicker()
        } label: {
            Group {
                if isPreparingImport || isCommittingImport {
                    ProgressView()
                        .tint(.white)
                } else {
                    Image(systemName: "plus")
                        .font(.system(size: 23, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 54, height: 54)
            .background(AppTheme.accent, in: Circle())
            .shadow(color: AppTheme.accent.opacity(0.28), radius: 12, y: 5)
        }
        .buttonStyle(NativePressButtonStyle())
        .disabled(isPreparingImport || isCommittingImport)
        .accessibilityLabel("导入真题包")
        .accessibilityIdentifier("question-bank-import")
        .padding(.trailing, 18)
        .padding(.bottom, 72)
    }

    private var filterControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                filterMenu(title: "年份", selection: $selectedYear, options: years)
                filterMenu(title: "考试类型", selection: $selectedExamType, options: examTypes)
                filterMenu(title: "模块", selection: $selectedModuleTitle, options: moduleTitles)
                Spacer(minLength: 0)
            }
            HStack(spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索试卷、题干或选项", text: $searchText)
                        .font(AppTheme.inputFont)
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
                HStack(spacing: 6) {
                    TextField("题号", text: $questionNumber)
                        .keyboardType(.numberPad)
                        .frame(width: 58)
                    if !questionNumber.isEmpty {
                        Button { questionNumber = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .frame(height: 40)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            }
        }
    }

    private func filterMenu(title: String, selection: Binding<String>, options: [String]) -> some View {
        Menu {
            Button("全部") { selection.wrappedValue = "" }
            ForEach(options, id: \.self) { value in
                Button(value) { selection.wrappedValue = value }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selection.wrappedValue.isEmpty ? title : selection.wrappedValue)
                    .lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold))
            }
            .font(AppTheme.auxiliaryFont.weight(.medium))
            .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : AppTheme.accent)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(AppTheme.secondaryBackground, in: Capsule())
        }
    }

    private func paperCard(_ record: QuestionBankRecord) -> some View {
        let paper = record.decoded(QuestionBankPaper.self)
        let modules = records.filter { $0.paperID == record.paperID && $0.kind == QuestionBankRepository.moduleKind }
            .sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
        let questionCount = records.filter { $0.paperID == record.paperID && $0.kind == QuestionBankRepository.questionKind }.count
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(paper?.title ?? record.title ?? "未命名试卷")
                    .font(AppTheme.cardTitleFont).foregroundStyle(.primary).lineLimit(2)
                Spacer(minLength: 8)
                Text(String(paper?.year ?? record.year ?? 0))
                    .font(AppTheme.auxiliaryFont.weight(.medium)).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text(paper?.examType ?? record.examType ?? "考试")
                if let volume = paper?.volume, !volume.isEmpty { Text(volume) }
                Text("\(questionCount) 道样题")
                Text("\(modules.count) 个模块")
            }
            .font(AppTheme.auxiliaryFont)
            .foregroundStyle(.secondary)
            if let source = paper?.source, !source.isEmpty {
                Text(source).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard(padding: 15)
    }

    @ViewBuilder
    private func paperDestination(for record: QuestionBankRecord) -> some View {
        if let target = questionTarget(for: record.paperID) {
            QuestionBankModuleView(
                paperID: record.paperID,
                moduleID: target.moduleID,
                initialQuestionNumber: String(target.questionNumber)
            )
        } else {
            QuestionBankPaperView(
                paperID: record.paperID,
                initialModuleTitle: selectedModuleTitle,
                initialQuestionNumber: questionNumber
            )
        }
    }

    private func questionTarget(for paperID: String) -> QuestionBankQuestionRouteTarget? {
        QuestionBankQuestionRoute.target(
            questionNumber: Int(questionNumber),
            paperID: paperID,
            selectedModuleTitle: selectedModuleTitle,
            records: records
        )
    }

    private func presentDocumentPicker() {
        guard !isPreparingImport, !isCommittingImport, activeImportSheet == nil else { return }
        let requestID = importSelection.beginPicker()
        importProgress.setMessage("文件选择器已打开")
        importLogger.info("native document picker opened")
        activeImportSheet = .picker(requestID)
    }

    private func handlePickedDocuments(_ requestID: UUID, _ urls: [URL]) {
        switch importSelection.receivePickedURLs(requestID: requestID, urls: urls) {
        case .selected(let selection):
            importLogger.info("native document picker returned a valid selection for request \(requestID.uuidString, privacy: .public)")
            showImportAlert = false
            importProgress.setMessage("\(selection.url.lastPathComponent)／准备读取")
            activeImportSheet = .preparing(requestID)
            // Selection starts preparation directly. The dismissal callback is
            // never required and cannot invalidate this request.
            Task { @MainActor in
                await Task.yield()
                startPendingPickedImportIfPossible(requestID: requestID)
            }
        case .emptySelection:
            reportPickerFailure(requestID: requestID, message: "文件选择器没有返回所选文件。请重新选择 JSON 或 ZIP 文件。")
        case .emptyURL:
            reportPickerFailure(requestID: requestID, message: "所选文件路径为空。请重新选择文件。")
        case .nonFileURL:
            reportPickerFailure(requestID: requestID, message: "选择器返回的不是本地文件，无法导入。")
        case .duplicate:
            importLogger.info("duplicate picker callback ignored for request \(requestID.uuidString, privacy: .public)")
        case .staleRequest:
            importLogger.info("stale picker callback ignored for request \(requestID.uuidString, privacy: .public)")
        }
    }

    private func handleDocumentPickerCancellation(_ requestID: UUID) {
        guard importSelection.cancelPickerRequest(requestID: requestID) else {
            importLogger.info("picker cancellation ignored after a selection was accepted")
            return
        }
        importProgress.setMessage("已取消选择")
        importLogger.info("native document picker reported cancellation")
        if case .picker(let activeID) = activeImportSheet, activeID == requestID {
            activeImportSheet = nil
        }
    }

    private func handleImportSheetDismissal() {
        if let requestID = importSelection.activePickerRequestID {
            switch importSelection.pickerWasDismissed(requestID: requestID) {
            case .awaitingCallback:
                importLogger.info("picker dismissed before callback; waiting for a late result")
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard importSelection.noteDismissalWithoutCallback(requestID: requestID) else { return }
                    importProgress.setMessage(nil)
                    showImportError("文件选择器关闭后没有返回文件。请重新选择。")
                }
                return
            case .selectionAlreadyReceived:
                // A selected URL remains valid even when the picker dismisses
                // before the flow view is ready to retain its new sheet item.
                if activeImportSheet == nil {
                    activeImportSheet = .preparing(requestID)
                }
                return
            case .alreadyAwaitingCallback:
                return
            case .previewAlreadyPresented:
                importSelection.finishPickerRequest(requestID: requestID)
            case .staleRequest:
                break
            }
        }

        guard activeImportSheet == nil else { return }
        if let importStagingDirectory {
            try? FileManager.default.removeItem(at: importStagingDirectory)
        }
        importStagingDirectory = nil
        processPendingExternalFileIfPossible()
    }

    private func startPendingPickedImportIfPossible(requestID: UUID) {
        guard case .preparing(let activeID) = activeImportSheet,
              activeID == requestID,
              !isPreparingImport,
              importWorker == nil,
              !isCommittingImport,
              let selection = importSelection.takePendingSelection(requestID: requestID)
        else { return }
        prepareImport(from: selection.url, source: .pickerCopy, pickerRequestID: requestID)
    }

    private func reportPickerFailure(requestID: UUID, message: String) {
        importSelection.failPickerRequest(requestID: requestID)
        importLogger.error("document picker returned an unusable selection for request \(requestID.uuidString, privacy: .public)")
        importProgress.setMessage(nil)
        activeImportSheet = nil
        showImportError(message)
    }

    private func processPendingExternalFileIfPossible() {
        guard rootTabSelection.wrappedValue == .questionBank,
              !isPreparingImport,
              importWorker == nil,
              !isCommittingImport,
              !showImportAlert,
              activeImportSheet == nil,
              let request = importRouter.takeNextRequest()
        else { return }

        importLogger.info("Files document-open request received")
        prepareImport(
            from: request.url,
            source: .filesOpenIn
        )
    }

    private func prepareImport(
        from url: URL,
        source: QuestionBankImportSource = .trustedLocalFile,
        pickerRequestID: UUID? = nil
    ) {
        guard !isPreparingImport, importWorker == nil, !isCommittingImport else { return }
        let runID = UUID()
        activeImportID = runID
        importWorkerID = runID
        isPreparingImport = true
        isCancellingImport = false
        importProgress.begin(runID: runID, fileName: url.lastPathComponent)
        let progress = importProgress
        let worker = Task.detached(priority: .utility) {
            try QuestionBankPackageImporter.prepare(from: url, source: source) { phase in
                Task { @MainActor in progress.update(runID: runID, phase: phase) }
            }
        }
        importWorker = worker
        Task { @MainActor in
            defer {
                if importWorkerID == runID {
                    importWorker = nil
                    importWorkerID = nil
                    if activeImportID == runID { activeImportID = nil }
                    isPreparingImport = false
                    if isCancellingImport {
                        isCancellingImport = false
                        importProgress.setMessage("已取消读取")
                    }
                    processPendingExternalFileIfPossible()
                }
            }
            do {
                let plan = try await worker.value
                guard activeImportID == runID else {
                    QuestionBankPackageImporter.cleanup(plan)
                    return
                }
                if let pickerRequestID,
                   !importSelection.markPreviewReady(requestID: pickerRequestID) {
                    QuestionBankPackageImporter.cleanup(plan)
                    return
                }
                importLogger.info("package validation finished: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count), errors=\(plan.errors.count)")
                importStagingDirectory = plan.stagingDirectory
                activeImportSheet = .preview(plan)
                importProgress.finish(runID: runID)
            } catch is CancellationError {
                if activeImportID == runID {
                    importProgress.finish(runID: runID, message: "已取消读取")
                }
            } catch {
                guard activeImportID == runID else { return }
                let errorType = String(reflecting: type(of: error))
                importLogger.error("package preparation failed (\(errorType, privacy: .public))")
                if let pickerRequestID {
                    importSelection.failPickerRequest(requestID: pickerRequestID)
                }
                importProgress.finish(runID: runID)
                activeImportSheet = nil
                showImportError(error.localizedDescription)
            }
        }
    }

    private func cancelPreparingImport() {
        guard isPreparingImport, let runID = activeImportID else { return }
        activeImportID = nil
        importWorker?.cancel()
        if let requestID = importSelection.activePickerRequestID {
            importSelection.failPickerRequest(requestID: requestID)
        }
        isCancellingImport = true
        importProgress.finish(runID: runID, message: "正在停止读取…")
        activeImportSheet = nil
        importLogger.info("question bank import cancelled by user")
    }

    private func commitImport(_ plan: QuestionBankImportPlan, decision: QuestionBankImportDecision,
                              batchMetadata: QuestionBankBatchMetadata?) {
        guard !isCommittingImport else { return }
        isCommittingImport = true
        inlineImportFailure = nil
        do {
            let duplicate = plan.paper.flatMap { QuestionBankRepository.duplicatePaper(for: $0, in: records) }
            let batchPreparation: QuestionBankBatchPreparation?
            if let batchMetadata {
                batchPreparation = try QuestionBankBatchRepository.prepare(
                    metadata: batchMetadata, plan: plan, records: records,
                    sourceRecords: batchSources, replacingPaperID: duplicate?.paperID
                )
            } else {
                batchPreparation = nil
            }
            try QuestionBankRepository.commit(
                plan, decision: decision, records: records, context: modelContext,
                batchPreparation: batchPreparation, batches: batchIndexes, sources: batchSources,
                batchMaterialLinks: batchMaterialLinks, batchQuestionLinks: batchQuestionLinks
            )
            isCommittingImport = false
            activeImportSheet = nil
            importLogger.info("atomic import committed: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count)")
            importAlertTitle = "导入完成"
            let batchSuffix = batchPreparation.map {
                "；批次新增唯一题 \($0.currentSourcePreview.uniqueQuestions)，精确重复 \($0.currentSourcePreview.duplicateQuestions)，待核 \($0.currentSourcePreview.suspectedQuestions + $0.currentSourcePreview.conflictingQuestions)"
            } ?? ""
            importAlertMessage = "已导入“\(plan.paper?.title ?? "试卷")”：\(plan.modules.count) 个模块、\(plan.questions.count) 道题目\(batchSuffix)。套卷成绩记录和学习库数据未更改。"
            showImportAlert = true
        } catch {
            isCommittingImport = false
            let errorType = String(reflecting: type(of: error))
            importLogger.error("atomic import failed and was rolled back (\(errorType, privacy: .public))")
            inlineImportFailure = error.localizedDescription
        }
    }

    private func showImportError(_ message: String) {
        importProgress.setMessage(nil)
        importAlertTitle = "导入未完成"
        importAlertMessage = message
        showImportAlert = true
    }

}

private struct QuestionBankImportPreparingView: View {
    let message: String
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)
                Text(message)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("取消读取", action: onCancel)
                    .buttonStyle(NativeSecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
            .navigationTitle("导入真题")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct QuestionBankImportPreview: View {
    let plan: QuestionBankImportPlan
    let isImporting: Bool
    let records: [QuestionBankRecord]
    let batchSources: [QuestionBankBatchSourceRecord]
    @Binding var importFailure: String?
    let onImport: (QuestionBankImportDecision, QuestionBankBatchMetadata?) -> Void
    let onCancel: () -> Void
    @State private var asksToReplace = false
    @State private var includesBatch: Bool
    @State private var family: QuestionBankBatchFamily?
    @State private var sourceID: String
    @State private var revision: String
    @State private var batchYear: String
    @State private var volumeID: String
    @State private var volumeName: String
    @State private var sessionID: String
    @State private var sessionName: String
    @State private var sourceProvinces: String
    @State private var provinceCode: String
    @State private var provinceName: String
    @State private var batchID: String
    @State private var batchName: String

    init(plan: QuestionBankImportPlan, records: [QuestionBankRecord],
         batchSources: [QuestionBankBatchSourceRecord], isImporting: Bool,
         importFailure: Binding<String?>,
         onImport: @escaping (QuestionBankImportDecision, QuestionBankBatchMetadata?) -> Void,
         onCancel: @escaping () -> Void) {
        self.plan = plan
        self.records = records
        self.batchSources = batchSources
        self.isImporting = isImporting
        self._importFailure = importFailure
        self.onImport = onImport
        self.onCancel = onCancel
        let metadata = plan.batchMetadata
        _includesBatch = State(initialValue: metadata != nil)
        _family = State(initialValue: metadata?.family)
        _sourceID = State(initialValue: metadata?.sourceID ?? "")
        _revision = State(initialValue: metadata?.revision ?? "")
        _batchYear = State(initialValue: metadata.map { String($0.year) } ?? "")
        _volumeID = State(initialValue: metadata?.volumeID ?? "")
        _volumeName = State(initialValue: metadata?.volumeName ?? "")
        _sessionID = State(initialValue: metadata?.sessionID ?? "")
        _sessionName = State(initialValue: metadata?.sessionName ?? "")
        _sourceProvinces = State(initialValue: (metadata?.sourceProvinces ?? [])
            .map { "\($0.code)|\($0.name)" }.joined(separator: "\n"))
        _provinceCode = State(initialValue: metadata?.provinceCode ?? "")
        _provinceName = State(initialValue: metadata?.provinceName ?? "")
        _batchID = State(initialValue: metadata?.batchID ?? "")
        _batchName = State(initialValue: metadata?.batchName ?? "")
    }

    private var currentBatchMetadata: QuestionBankBatchMetadata? {
        guard includesBatch, let family else { return nil }
        let year = Int(batchYear.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        let passthrough = plan.batchMetadata?.family == family ? plan.batchMetadata : nil
        switch family {
        case .national:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: volumeID, volumeName: volumeName, sessionID: passthrough?.sessionID,
                sessionName: passthrough?.sessionName, sourceProvinces: passthrough?.sourceProvinces,
                provinceCode: passthrough?.provinceCode, provinceName: passthrough?.provinceName,
                batchID: passthrough?.batchID, batchName: passthrough?.batchName)
        case .joint:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: passthrough?.volumeID, volumeName: passthrough?.volumeName,
                sessionID: sessionID, sessionName: sessionName,
                sourceProvinces: parseSourceProvinces(), provinceCode: passthrough?.provinceCode,
                provinceName: passthrough?.provinceName, batchID: passthrough?.batchID,
                batchName: passthrough?.batchName)
        case .provincial:
            return QuestionBankBatchMetadata(family: family, sourceID: sourceID, revision: revision, year: year,
                volumeID: passthrough?.volumeID, volumeName: passthrough?.volumeName,
                sessionID: passthrough?.sessionID, sessionName: passthrough?.sessionName,
                sourceProvinces: passthrough?.sourceProvinces,
                provinceCode: provinceCode, provinceName: provinceName,
                batchID: batchID, batchName: batchName)
        }
    }

    private var batchPreparationResult: Result<QuestionBankBatchPreparation, Error>? {
        guard plan.canImport, let metadata = currentBatchMetadata, metadata.validationError == nil else { return nil }
        let duplicate = replacementPaperRecord
        return Result {
            try QuestionBankBatchRepository.prepare(metadata: metadata, plan: plan, records: records,
                sourceRecords: batchSources, replacingPaperID: duplicate?.paperID)
        }
    }

    private var duplicatePaperRecord: QuestionBankRecord? {
        plan.paper.flatMap { QuestionBankRepository.duplicatePaper(for: $0, in: records) }
    }

    private var existingSourcePaperRecord: QuestionBankRecord? {
        guard includesBatch, let metadata = currentBatchMetadata else { return nil }
        let stableSourceID = metadata.sourceID.trimmedNonempty
        guard let source = batchSources.first(where: { $0.sourceID == stableSourceID }) else { return nil }
        return records.first {
            $0.paperID == source.paperID && $0.kind == QuestionBankRepository.paperKind
        }
    }

    private var replacementPaperRecord: QuestionBankRecord? {
        existingSourcePaperRecord ?? duplicatePaperRecord
    }

    private var replacementTitle: String? {
        replacementPaperRecord.map { row in
            row.decoded(QuestionBankPaper.self)?.title ?? row.title ?? "未命名试卷"
        }
    }

    private func parseSourceProvinces() -> [QuestionBankSourceProvince] {
        return sourceProvinceLines.compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { return nil }
            return QuestionBankSourceProvince(code: String(parts[0]).trimmedNonempty,
                name: String(parts[1]).trimmedNonempty)
        }
    }

    private var sourceProvinceLines: [String] {
        var lines = sourceProvinces
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
        while lines.last?.trimmedNonempty.isEmpty == true { lines.removeLast() }
        return lines
    }

    private var hasMalformedSourceProvinceLine: Bool {
        sourceProvinceLines.contains { line in
            let parts = line.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            return parts.count != 2 || parts.contains { String($0).trimmedNonempty.isEmpty }
        }
    }

    private func submit(_ decision: QuestionBankImportDecision) {
        onImport(decision, currentBatchMetadata)
    }

    var body: some View {
        let batchResult = batchPreparationResult
        let metadataError: String? = {
            guard includesBatch else { return nil }
            guard let family else { return "请选择批次类别。" }
            guard let metadata = currentBatchMetadata else { return "请填写完整批次信息。" }
            if let existingSourcePaperRecord, let duplicatePaperRecord,
               existingSourcePaperRecord.paperID != duplicatePaperRecord.paperID {
                return QuestionBankBatchFailure.conflictingReplacementTargets(metadata.sourceID)
                    .localizedDescription
            }
            if family == .joint && hasMalformedSourceProvinceLine {
                return "来源省份每行必须按“代码|名称”填写；无效行不会被忽略。"
            }
            if let message = metadata.validationError { return message }
            if let batchResult, case .failure(let error) = batchResult { return error.localizedDescription }
            return nil
        }()
        let preparedBatch: QuestionBankBatchPreparation? = {
            guard let batchResult, case .success(let preparation) = batchResult else { return nil }
            return preparation
        }()
        return NavigationStack {
            Form {
                if let importFailure {
                    Section("导入失败，原有试卷未更改") {
                        Label(importFailure, systemImage: "exclamationmark.triangle.fill")
                            .font(AppTheme.bodyFont).foregroundStyle(AppTheme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Section("试卷预览") {
                    LabeledContent("名称", value: plan.paper?.title ?? "无法识别")
                    LabeledContent("年份 / 类型", value: plan.paper.map { "\($0.year) · \($0.examType)" } ?? "—")
                    LabeledContent("模块", value: "\(plan.modules.count) 个")
                    LabeledContent("共用材料", value: "\(plan.materials.count) 份")
                    LabeledContent("题目", value: "\(plan.questions.count) 道")
                    LabeledContent("图片", value: "\(plan.assets.count) 张")
                }
                Section("跨卷批次") {
                    Toggle("加入跨卷批次", isOn: $includesBatch)
                    if includesBatch {
                        Picker("批次类别", selection: $family) {
                            Text("请选择类别").tag(QuestionBankBatchFamily?.none)
                            ForEach(QuestionBankBatchFamily.allCases, id: \.self) { value in
                                Text(value.title).tag(Optional(value))
                            }
                        }
                        TextField("来源标识 sourceID", text: $sourceID).textInputAutocapitalization(.never)
                        TextField("来源修订 revision", text: $revision).textInputAutocapitalization(.never)
                        TextField("批次年份 year", text: $batchYear).keyboardType(.numberPad)
                        if let family {
                            switch family {
                            case .national:
                                TextField("明确卷别 ID volumeID", text: $volumeID)
                                TextField("明确卷别名称 volumeName", text: $volumeName)
                            case .joint:
                                TextField("明确场次 ID sessionID", text: $sessionID)
                                TextField("明确场次名称 sessionName", text: $sessionName)
                                TextField("来源省份：每行代码|名称", text: $sourceProvinces, axis: .vertical)
                                    .lineLimit(1...4)
                            case .provincial:
                                TextField("省份代码 provinceCode", text: $provinceCode)
                                TextField("省份名称 provinceName", text: $provinceName)
                                TextField("批次 ID batchID", text: $batchID)
                                TextField("批次名称 batchName", text: $batchName)
                            }
                        }
                        if let metadataError {
                            Label(metadataError, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if let preview = preparedBatch?.currentSourcePreview {
                            LabeledContent("题目", value: "新增唯一 \(preview.uniqueQuestions) · 精确重复 \(preview.duplicateQuestions) · 疑似 \(preview.suspectedQuestions) · 冲突 \(preview.conflictingQuestions)")
                            LabeledContent("材料", value: "新增唯一 \(preview.uniqueMaterials) · 精确重复 \(preview.duplicateMaterials) · 待核 \(preview.pendingMaterials)")
                        }
                        Text("批次只新增索引与来源关联，不复制正文或图片；整卷替换仍按上方确认执行。卷别、省份、场次和批次必须由来源明确提供，不从标题或文件名猜测。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    } else if plan.batchMetadata == nil {
                        Text("旧版 v1 文件可继续作为单卷导入；需要归入批次时再填写明确元数据。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
                if !plan.errors.isEmpty {
                    Section("校验错误（修复后再导入）") {
                        ForEach(Array(plan.errors.enumerated()), id: \.offset) { _, error in
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(AppTheme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Section("校验结果") {
                        Label("结构、题号、答案、图片文件及关联均已通过检查", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.success)
                        Text("图片将以文件保存；列表不会加载图片字节。导入只新增真题库内容，不生成解析或作答记录。")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("确认导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel).disabled(isImporting)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "正在导入…" : "导入试卷") {
                        if replacementTitle != nil { asksToReplace = true }
                        else { submit(.add) }
                    }
                    .disabled(!plan.canImport || isImporting
                        || (includesBatch && (metadataError != nil || preparedBatch == nil)))
                }
            }
            .confirmationDialog(
                "检测到重复试卷",
                isPresented: $asksToReplace,
                titleVisibility: .visible
            ) {
                Button("替换已有的“\(replacementTitle ?? "同名试卷")”", role: .destructive) {
                    submit(.replaceExisting)
                }
                Button("取消导入", role: .cancel) { }
            } message: {
                Text("按来源标识的修订关系、试卷 ID，或年份、考试类型、卷别和名称识别替换目标。替换失败时仍保留原数据。")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

private struct QuestionBankPaperView: View {
    @Query private var records: [QuestionBankRecord]
    let paperID: String
    @State private var selectedModuleTitle: String
    @State private var questionNumber: String

    init(paperID: String, initialModuleTitle: String, initialQuestionNumber: String) {
        self.paperID = paperID
        _selectedModuleTitle = State(initialValue: initialModuleTitle)
        _questionNumber = State(initialValue: initialQuestionNumber)
    }

    private var paperRecord: QuestionBankRecord? {
        records.first { $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind }
    }
    private var paper: QuestionBankPaper? { paperRecord?.decoded(QuestionBankPaper.self) }
    private var modules: [QuestionBankRecord] {
        records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind }
            .filter { selectedModuleTitle.isEmpty || $0.title == selectedModuleTitle }
            .filter { module in
                guard let number = Int(questionNumber), number > 0 else { return true }
                return records.contains { $0.paperID == paperID && $0.moduleID == module.stableID
                    && $0.kind == QuestionBankRepository.questionKind && $0.questionNumber == number }
            }
            .sorted { ($0.sequence ?? 0) < ($1.sequence ?? 0) }
    }
    private var allModuleTitles: [String] {
        Array(Set(records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind }
            .compactMap(\.title))).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let paper {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(paper.title).font(AppTheme.sectionTitleFont)
                        Text([String(paper.year), paper.examType, paper.volume]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .padding(.bottom, 2)
                }
                HStack(spacing: 8) {
                    Menu {
                        Button("全部模块") { selectedModuleTitle = "" }
                        ForEach(allModuleTitles, id: \.self) { title in Button(title) { selectedModuleTitle = title } }
                    } label: { filterLabel(selectedModuleTitle.isEmpty ? "全部模块" : selectedModuleTitle) }
                    HStack(spacing: 6) {
                        TextField("题号", text: $questionNumber).keyboardType(.numberPad).frame(width: 64)
                        if !questionNumber.isEmpty {
                            Button { questionNumber = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 11).frame(height: 34)
                    .background(AppTheme.secondaryBackground, in: Capsule())
                    Spacer()
                }
                if modules.isEmpty {
                    NativeStatusCard(title: "没有匹配模块", detail: "更改模块或题号筛选条件。", systemImage: "line.3.horizontal.decrease", color: AppTheme.accent)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(modules, id: \.compoundID) { moduleRecord in
                            let module = moduleRecord.decoded(QuestionBankModule.self)
                            let count = records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind && $0.moduleID == moduleRecord.stableID }.count
                            NavigationLink {
                                QuestionBankModuleView(paperID: paperID, moduleID: moduleRecord.stableID, initialQuestionNumber: questionNumber)
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text(String(format: "%02d", module?.sequence ?? moduleRecord.sequence ?? 0))
                                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(width: 36, height: 34, alignment: .leading)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(module?.title ?? moduleRecord.title ?? "模块")
                                                .font(AppTheme.sectionTitleFont).foregroundStyle(.primary)
                                            Text(count == 0 ? "本次样本未收录题目" : "\(String(count)) 道样题")
                                                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                    .padding(.vertical, 14)
                                    .overlay(alignment: .bottom) {
                                        Rectangle()
                                            .fill(Color(uiColor: .separator).opacity(0.45))
                                            .frame(height: 1)
                                    }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("question-bank-module-\(moduleRecord.stableID)")
                            }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("模块目录")
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageTabBarHidden()
    }

    private func filterLabel(_ value: String) -> some View {
        HStack(spacing: 5) { Text(value).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            .font(AppTheme.auxiliaryFont.weight(.medium)).foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 11).frame(height: 34).background(AppTheme.secondaryBackground, in: Capsule())
    }
}
