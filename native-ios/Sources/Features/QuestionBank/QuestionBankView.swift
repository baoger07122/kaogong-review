import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit
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
                                    QuestionBankPaperView(
                                        paperID: record.paperID,
                                        initialModuleTitle: selectedModuleTitle,
                                        initialQuestionNumber: questionNumber
                                    )
                                } label: {
                                    paperCard(record)
                                }
                                .buttonStyle(.plain)
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
                    duplicateTitle: plan.paper.flatMap { QuestionBankRepository.duplicatePaper(for: $0, in: records)?.title },
                    isImporting: isCommittingImport,
                    importFailure: $inlineImportFailure,
                    onImport: { decision in commitImport(plan, decision: decision) },
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
                Text("\(paper?.year ?? record.year ?? 0)")
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

    private func commitImport(_ plan: QuestionBankImportPlan, decision: QuestionBankImportDecision) {
        guard !isCommittingImport else { return }
        isCommittingImport = true
        inlineImportFailure = nil
        do {
            try QuestionBankRepository.commit(plan, decision: decision, records: records, context: modelContext)
            isCommittingImport = false
            activeImportSheet = nil
            importLogger.info("atomic import committed: modules=\(plan.modules.count), questions=\(plan.questions.count), assets=\(plan.assets.count)")
            importAlertTitle = "导入完成"
            importAlertMessage = "已导入“\(plan.paper?.title ?? "试卷")”：\(plan.modules.count) 个模块、\(plan.questions.count) 道题目。套卷成绩记录和学习库数据未更改。"
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
    let duplicateTitle: String?
    let isImporting: Bool
    @Binding var importFailure: String?
    let onImport: (QuestionBankImportDecision) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var asksToReplace = false

    var body: some View {
        NavigationStack {
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
                        if duplicateTitle != nil { asksToReplace = true }
                        else { onImport(.add) }
                    }
                    .disabled(!plan.canImport || isImporting)
                }
            }
            .confirmationDialog(
                "检测到重复试卷",
                isPresented: $asksToReplace,
                titleVisibility: .visible
            ) {
                Button("替换已有的“\(duplicateTitle ?? "同名试卷")”", role: .destructive) {
                    onImport(.replaceExisting)
                }
                Button("取消导入", role: .cancel) { }
            } message: {
                Text("按试卷ID或年份、考试类型、卷别和名称识别为同一套试卷。替换失败时仍保留原数据。")
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
                    VStack(alignment: .leading, spacing: 6) {
                        Text(paper.title).font(AppTheme.pageTitleFont)
                        Text("\(paper.year) · \(paper.examType)\(paper.volume.isEmpty ? "" : " · \(paper.volume)")")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nativeCard()
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
                    LazyVStack(spacing: 10) {
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
                                        .frame(width: 38, height: 38)
                                        .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(module?.title ?? moduleRecord.title ?? "模块").font(AppTheme.sectionTitleFont).foregroundStyle(.primary)
                                            Spacer()
                                            Text("\(count) 题").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                        if let instruction = module?.instruction, !instruction.isEmpty {
                                            Text(instruction).font(AppTheme.bodyFont).foregroundStyle(.secondary).lineLimit(3)
                                        }
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .nativeCard(padding: 14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("试卷结构")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func filterLabel(_ value: String) -> some View {
        HStack(spacing: 5) { Text(value).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)) }
            .font(AppTheme.auxiliaryFont.weight(.medium)).foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 11).frame(height: 34).background(AppTheme.secondaryBackground, in: Capsule())
    }
}

private struct QuestionBankModuleView: View {
    @Query private var records: [QuestionBankRecord]
    let paperID: String
    let moduleID: String
    @State private var questionNumber: String

    init(paperID: String, moduleID: String, initialQuestionNumber: String) {
        self.paperID = paperID
        self.moduleID = moduleID
        _questionNumber = State(initialValue: initialQuestionNumber)
    }

    private var module: QuestionBankModule? {
        records.first { $0.paperID == paperID && $0.stableID == moduleID && $0.kind == QuestionBankRepository.moduleKind }?.decoded(QuestionBankModule.self)
    }
    private var questions: [QuestionBankRecord] {
        records.filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind && $0.moduleID == moduleID }
            .filter { questionNumber.isEmpty || String($0.questionNumber ?? 0).contains(questionNumber) }
            .sorted { ($0.questionNumber ?? 0) < ($1.questionNumber ?? 0) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let module {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(module.title).font(AppTheme.pageTitleFont)
                        Text(module.instruction).font(AppTheme.bodyFont).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nativeCard()
                }
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("按题号查找", text: $questionNumber).keyboardType(.numberPad)
                    if !questionNumber.isEmpty {
                        Button { questionNumber = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                            .buttonStyle(.plain)
                    }
                }
                .font(AppTheme.inputFont).padding(.horizontal, 12).frame(height: 40)
                .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
                if questions.isEmpty {
                    NativeStatusCard(title: "当前没有样题", detail: "这个模块已作为试卷结构导入，样题可能尚未整理。", systemImage: "doc.text.magnifyingglass", color: AppTheme.accent)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(questions, id: \.compoundID) { record in
                            if let question = record.decoded(QuestionBankQuestion.self) {
                                NavigationLink {
                                    QuestionBankQuestionView(paperID: paperID, questionID: question.id)
                                } label: {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("第\(question.number)题 · \(question.type.isEmpty ? question.subject : question.type)")
                                            .font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent)
                                        Text(question.stem.isEmpty ? "图片题" : question.stem)
                                            .font(AppTheme.cardTitleFont).foregroundStyle(.primary).lineLimit(3)
                                        if question.materialID.isEmpty == false {
                                            Label("含共用材料", systemImage: "doc.on.doc").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .nativeCard(padding: 15)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(module?.title ?? "模块题目")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct QuestionBankQuestionView: View {
    @Query private var records: [QuestionBankRecord]
    let paperID: String
    let questionID: String

    private var question: QuestionBankQuestion? {
        records.first { $0.paperID == paperID && $0.stableID == questionID && $0.kind == QuestionBankRepository.questionKind }?.decoded(QuestionBankQuestion.self)
    }
    private var module: QuestionBankModule? {
        guard let moduleID = question?.moduleID else { return nil }
        return records.first { $0.paperID == paperID && $0.stableID == moduleID && $0.kind == QuestionBankRepository.moduleKind }?.decoded(QuestionBankModule.self)
    }
    private var material: QuestionBankMaterial? {
        guard let materialID = question?.materialID, !materialID.isEmpty else { return nil }
        return records.first { $0.paperID == paperID && $0.stableID == materialID && $0.kind == QuestionBankRepository.materialKind }?.decoded(QuestionBankMaterial.self)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let module {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(module.title).font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent)
                        if !module.instruction.isEmpty { Text(module.instruction).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                    }
                }
                if let material {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("共用材料").font(AppTheme.sectionTitleFont)
                        if !material.text.isEmpty { Text(material.text).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true) }
                        if !material.imageAssetID.isEmpty, let asset = assetRecord(material.imageAssetID) {
                            QuestionBankLocalImage(asset: asset)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nativeCard()
                }
                if let question {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("第\(question.number)题").font(AppTheme.sectionTitleFont)
                        if !question.stem.isEmpty {
                            Text(question.stem).font(AppTheme.questionTextFont).lineSpacing(AppTheme.questionLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if !question.stemImageAssetID.isEmpty, let asset = assetRecord(question.stemImageAssetID) {
                            QuestionBankLocalImage(asset: asset)
                        }
                        ForEach(question.options) { option in
                            optionRow(option, question: question)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                            Text("正确答案").foregroundStyle(.secondary)
                            Text(question.answer).fontWeight(.semibold)
                        }
                        .font(AppTheme.bodyFont)
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .nativeCard()
                } else {
                    NativeStatusCard(title: "题目不存在", detail: "此题可能已被试卷替换。", systemImage: "exclamationmark.triangle", color: AppTheme.warning)
                }
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("第\(question?.number ?? 0)题")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func optionRow(_ option: QuestionBankOption, question: QuestionBankQuestion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(option.id).font(AppTheme.bodyFont.weight(.semibold)).frame(width: 25, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if !option.text.isEmpty { Text(option.text).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true) }
                if !option.imageAssetID.isEmpty, let asset = assetRecord(option.imageAssetID) {
                    QuestionBankLocalImage(asset: asset)
                }
            }
            Spacer(minLength: 0)
            if question.answer == option.id {
                Image(systemName: "checkmark").foregroundStyle(AppTheme.success).fontWeight(.semibold)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func assetRecord(_ id: String) -> QuestionBankRecord? {
        records.first { $0.paperID == paperID && $0.stableID == id && $0.kind == QuestionBankRepository.assetKind }
    }
}

private struct QuestionBankLocalImage: View {
    let asset: QuestionBankRecord
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppTheme.groupedBackground)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 90)
            }
        }
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: asset.assetRelativePath) {
            guard let url = QuestionBankAssetStore.url(for: asset.assetRelativePath) else { return }
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            image = data.flatMap(UIImage.init(data:))
        }
    }
}

private extension QuestionBankRecord {
    func decoded<Value: Decodable>(_ type: Value.Type) -> Value? { try? JSONDecoder().decode(type, from: payload) }
}
