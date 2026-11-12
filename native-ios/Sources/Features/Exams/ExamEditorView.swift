import Observation
import SwiftData
import SwiftUI
import UIKit

struct ExamEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let recordID: String?
    @State private var draft: ExamDraft
    @State private var metricsState: ExamModuleMetricsState
    @State private var timeInputBuffer = ExamTimeInputBuffer()
    @State private var reviewNoteEditorSession = NativeRichTextEditorSession()
    @State private var reviewNoteEditorSessionID = UUID()
    @State private var showDelete = false
    @State private var showReportParser = false
    @State private var reparseMessage: String?
    @State private var editorErrorMessage: String?

    init(record: StoredRecord? = nil, preferredType: LibraryReviewSource? = nil) {
        recordID = record?.recordID
        var value = ExamDraft(record: record)
        if record == nil, let preferredType, preferredType != .pending { value.examType = preferredType }
        _draft = State(initialValue: value)
        _metricsState = State(initialValue: ExamModuleMetricsState(lines: value.moduleResults))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ExamAttemptSection(draft: draft)
                ExamReportSummarySection(
                    rawReport: draft.rawReport,
                    reparseMessage: reparseMessage,
                    onEdit: { showReportParser = true }
                )
                ExamResultSection(draft: draft, metricsState: metricsState, timeInputBuffer: timeInputBuffer)
                ExamScoreSection(draft: draft)
                ExamLinkedErrorsSection(draft: draft, metricsState: metricsState)
                ExamReviewNoteSection(
                    initialHTML: draft.reviewNote,
                    documentID: "exam-review-note:\(recordID ?? "new")",
                    sessionID: reviewNoteEditorSessionID,
                    session: reviewNoteEditorSession
                )
                ExamModuleMetricsObserver(draft: draft, metricsState: metricsState)
            }
            .padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(recordID == nil ? "记录套卷" : "编辑套卷")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                ExamSaveToolbarButton(draft: draft, action: save)
            }
            if recordID != nil {
                ToolbarItem(placement: .bottomBar) {
                    Button("删除", role: .destructive) { showDelete = true }
                }
            }
        }
        .confirmationDialog("删除本次考试记录", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: {
            Text("关联错题会保留，只解除与本次考试的关系。")
        }
        .alert("操作失败", isPresented: Binding(
            get: { editorErrorMessage != nil },
            set: { if !$0 { editorErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { editorErrorMessage = nil }
        } message: {
            Text(editorErrorMessage ?? "")
        }
        .sheet(isPresented: $showReportParser) {
            ExamReportParserSheet(
                draft: draft,
                onSaveText: { rawText in
                    draft.rawReport = rawText
                    showReportParser = false
                },
                onApplyParsed: { rawText, result, replacing in
                    applyParsedReport(rawText, result: result, replacing: replacing)
                }
            )
        }
    }

    private func applyParsedReport(
        _ rawText: String,
        result: ExamReportParser.Result,
        replacing: Bool
    ) {
        draft.rawReport = rawText
        var conflicts = result.duplicateConflicts
        if replacing {
            draft.moduleResults = result.lines
        } else {
            let merged = ExamReportMergePolicy.merge(
                result.lines,
                into: draft.moduleResults,
                carrying: result.duplicateConflicts
            )
            draft.moduleResults = merged.lines
            conflicts = merged.conflicts
        }

        var parts: [String] = []
        if !conflicts.isEmpty { parts.append("重复或冲突项：\(conflicts.joined(separator: "、"))，请检查") }
        if !result.unparsedLines.isEmpty { parts.append("未识别 \(result.unparsedLines.count) 行，原文已保留") }
        if !result.warnings.isEmpty { parts.append(contentsOf: result.warnings) }
        if parts.isEmpty {
            reparseMessage = replacing
                ? "已载入 \(draft.moduleResults.count) 项成绩，可逐项核对。"
                : "已合并空缺字段，原有手工内容保留。"
        } else {
            reparseMessage = parts.joined(separator: "；")
        }
        showReportParser = false
    }

    private func save() {
        let committed = timeInputBuffer.applyingPending(to: draft.moduleResults)
        guard committed.invalidIDs.isEmpty else {
            let subjects = committed.invalidIDs.compactMap { id in
                draft.moduleResults.first(where: { $0.id == id })?.subject
            }
            let detail = subjects.isEmpty ? "" : "：\(subjects.joined(separator: "、"))"
            editorErrorMessage = "请检查用时格式\(detail)，例如 1:25 或 1小时25分。修改后的内容尚未保存。"
            return
        }
        if committed.lines != draft.moduleResults { draft.moduleResults = committed.lines }
        metricsState.updateIfNeeded(from: committed.lines)

        let noteCaptureStart = ProcessInfo.processInfo.systemUptime
        reviewNoteEditorSession.commitCompositionIfNeeded()
        if let latestHTML = reviewNoteEditorSession.captureSnapshot()?.html
            ?? reviewNoteEditorSession.latestHTML() {
            draft.reviewNote = latestHTML
        }
        LibraryPerformanceLog.markIfSlow("exam.editor.note-capture", since: noteCaptureStart)

        do {
            let records = try modelContext.fetch(FetchDescriptor<StoredRecord>())
            _ = try ExamRepository.save(
                draft,
                derivedMetrics: metricsState.metrics,
                records: records,
                context: modelContext
            )
            dismiss()
        } catch {
            editorErrorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    private func remove() {
        guard let recordID else { return }
        do {
            let records = try modelContext.fetch(FetchDescriptor<StoredRecord>())
            try ExamRepository.remove(id: recordID, records: records, context: modelContext)
            dismiss()
        } catch {
            editorErrorMessage = "删除失败：\(error.localizedDescription)"
        }
    }
}

@MainActor
@Observable
private final class ExamModuleMetricsState {
    private(set) var metrics: ExamDerivedMetrics
    @ObservationIgnored private var sourceLines: [ExamModuleResult]

    init(lines: [ExamModuleResult]) {
        sourceLines = lines
        metrics = ExamReportParser.metrics(for: lines)
    }

    func updateIfNeeded(from lines: [ExamModuleResult]) {
        guard sourceLines != lines else { return }
        sourceLines = lines
        let started = ProcessInfo.processInfo.systemUptime
        metrics = ExamReportParser.metrics(for: lines)
        LibraryPerformanceLog.markIfSlow("exam.editor.module-metrics", since: started)
    }
}

private struct ExamModuleMetricsObserver: View {
    let draft: ExamDraft
    let metricsState: ExamModuleMetricsState

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear { metricsState.updateIfNeeded(from: draft.moduleResults) }
            .onChange(of: draft.moduleResults) { _, lines in
                metricsState.updateIfNeeded(from: lines)
            }
    }
}

private struct ExamSaveToolbarButton: View {
    let draft: ExamDraft
    let action: () -> Void

    var body: some View {
        Button("保存", action: action)
            .disabled(
                draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || draft.moduleResults.contains { $0.subject == ExamModuleCatalog.placeholderSubject }
            )
    }
}

private struct ExamAttemptSection: View {
    @Bindable var draft: ExamDraft

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        ExamEditorFieldLabel(title: "考试类型")
                        Picker("考试类型", selection: $draft.examType) {
                            Text("真题").tag(LibraryReviewSource.real)
                            Text("模拟卷").tag(LibraryReviewSource.mock)
                            if draft.examType == .pending { Text("未分类").tag(LibraryReviewSource.pending) }
                        }
                        .pickerStyle(.segmented)
                        .font(.system(size: 12.5))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(alignment: .leading, spacing: 5) {
                        ExamEditorFieldLabel(title: "考试日期")
                        DatePicker("考试日期", selection: $draft.examDate, displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.compact)
                            .font(.system(size: 12.5))
                            .padding(.horizontal, 8)
                            .frame(height: 38)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
                    }
                }
                ExamEditorFieldLabel(title: "套卷名称")
                TextField("套卷名称", text: $draft.name)
                    .textFieldStyle(ErrorFormTextFieldStyle())
            }
        }
    }
}

private struct ExamReportSummarySection: View {
    let rawReport: String
    let reparseMessage: String?
    let onEdit: () -> Void

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ExamEditorSectionTitle(title: "成绩报告原文")
                    Spacer()
                    Button(action: onEdit) {
                        Label("粘贴 / 编辑", systemImage: "doc.on.clipboard")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }
                Text(rawReport.isEmpty ? "尚未粘贴成绩报告原文" : rawReport)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(rawReport.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                if let reparseMessage {
                    Text(reparseMessage).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct ExamScoreSection: View {
    @Bindable var draft: ExamDraft

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 9) {
                ExamEditorSectionTitle(title: "实际得分")
                HStack(spacing: 8) {
                    TextField("实际得分", text: $draft.score)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(ErrorFormTextFieldStyle())
                    Text("/").foregroundStyle(.secondary)
                    TextField("满分", text: $draft.maximumScore)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(ErrorFormTextFieldStyle())
                }
                Text("得分与正确率分别记录；正确率按有效题数加权计算。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExamResultSection: View {
    @Bindable var draft: ExamDraft
    let metricsState: ExamModuleMetricsState
    let timeInputBuffer: ExamTimeInputBuffer

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    ExamEditorSectionTitle(title: "可编辑的模块成绩")
                    Spacer()
                    Button {
                        draft.moduleResults.append(ExamModuleResult(
                            subject: ExamModuleCatalog.placeholderSubject,
                            parentSubject: ExamModuleCatalog.placeholderSubject
                        ))
                    } label: {
                        Label("手动添加", systemImage: "plus")
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                }

                if draft.moduleResults.isEmpty {
                    Text("解析后可修改各项；也可以直接手动添加。留空的字段会按未知处理，不按 0 统计。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    if draft.moduleResults.contains(where: { $0.subject == ExamModuleCatalog.placeholderSubject }) {
                        Text("请先为手动添加的每一项选择模块，未选择时不能保存。")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(AppTheme.warning)
                    }
                    ScrollView(.horizontal) {
                        VStack(spacing: 5) {
                            HStack(spacing: ExamModuleColumn.spacing) {
                                header("模块", width: ExamModuleColumn.module)
                                header("总题数", width: ExamModuleColumn.total)
                                header("答对", width: ExamModuleColumn.correct)
                                header("报告率", width: ExamModuleColumn.accuracy)
                                header("用时", width: ExamModuleColumn.time)
                                Text("").frame(width: ExamModuleColumn.delete)
                            }
                            ForEach($draft.moduleResults) { $line in
                                ExamModuleResultRow(
                                    line: $line,
                                    draft: draft,
                                    timeInputBuffer: timeInputBuffer
                                )
                            }
                        }
                        .padding(.vertical, 2)
                    }
                    .scrollIndicators(.hidden)
                }

                ExamDerivedMetricsSummary(metricsState: metricsState)
            }
        }
    }

    private func header(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(width: width, alignment: .leading)
    }
}

private enum ExamModuleColumn {
    static let module: CGFloat = 154
    static let total: CGFloat = 78
    static let correct: CGFloat = 70
    static let accuracy: CGFloat = 88
    static let time: CGFloat = 92
    static let delete: CGFloat = 32
    static let spacing: CGFloat = 6
}

private struct ExamModuleResultRow: View {
    @Binding var line: ExamModuleResult
    let draft: ExamDraft
    let timeInputBuffer: ExamTimeInputBuffer

    var body: some View {
        HStack(spacing: ExamModuleColumn.spacing) {
            Picker("模块", selection: $line.subject) {
                if line.subject == ExamModuleCatalog.placeholderSubject {
                    Text("选择模块").tag(ExamModuleCatalog.placeholderSubject)
                } else if !ExamModuleCatalog.selectableSubjects.contains(line.subject) {
                    Text("历史模块 · \(line.subject)").tag(line.subject)
                }
                ForEach(ExamModuleCatalog.topLevel, id: \.self) { parent in
                    if let children = ExamModuleCatalog.children[parent], !children.isEmpty {
                        Section(parent) {
                            Text(parent).tag(parent)
                            ForEach(children, id: \.self) { Text($0).tag($0) }
                        }
                    } else {
                        Text(parent).tag(parent)
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .font(.system(size: 12.5))
            .frame(width: ExamModuleColumn.module, height: 38, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
            .accessibilityLabel("模块，当前 \(line.subject)")

            resultField("总题数", text: $line.totalQuestions, keyboard: .numberPad, width: ExamModuleColumn.total)
            resultField("答对", text: $line.correctCount, keyboard: .numberPad, width: ExamModuleColumn.correct)
            resultField("报告率", text: $line.reportedAccuracy, keyboard: .decimalPad, width: ExamModuleColumn.accuracy, suffix: "%")
            ExamTimeField(
                seconds: $line.timeSeconds,
                rowID: line.id,
                inputBuffer: timeInputBuffer,
                width: ExamModuleColumn.time
            )
            Button {
                draft.moduleResults.removeAll { $0.id == line.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(AppTheme.danger)
                    .font(.system(size: 12))
                    .frame(width: ExamModuleColumn.delete, height: 38)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除\(line.subject)")
        }
        .onChange(of: line.subject) { _, value in
            line.parentSubject = ExamModuleCatalog.parentSubject(for: value)
        }
    }

    private func resultField(
        _ title: String,
        text: Binding<String>,
        keyboard: UIKeyboardType,
        width: CGFloat,
        suffix: String = ""
    ) -> some View {
        HStack(spacing: 2) {
            TextField("", text: text)
                .keyboardType(keyboard)
                .multilineTextAlignment(.center)
                .textFieldStyle(ErrorFormTextFieldStyle())
                .accessibilityLabel(title)
            if !suffix.isEmpty {
                Text(suffix).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(width: width)
    }
}

@MainActor
private final class ExamTimeInputBuffer {
    private var pendingValues: [String: String] = [:]

    func stage(rowID: String, rawValue: String) {
        pendingValues[rowID] = rawValue
    }

    func hasPendingValue(for rowID: String) -> Bool {
        pendingValues[rowID] != nil
    }

    func commit(rowID: String) -> String? {
        guard let rawValue = pendingValues[rowID],
              let value = normalizedValue(rawValue) else { return nil }
        pendingValues.removeValue(forKey: rowID)
        return value
    }

    func applyingPending(to lines: [ExamModuleResult]) -> (lines: [ExamModuleResult], invalidIDs: [String]) {
        let activeIDs = Set(lines.map(\.id))
        pendingValues = pendingValues.filter { activeIDs.contains($0.key) }
        let invalidIDs = pendingValues.compactMap { rowID, rawValue in
            normalizedValue(rawValue) == nil ? rowID : nil
        }
        guard invalidIDs.isEmpty else { return (lines, invalidIDs) }

        var result = lines
        for index in result.indices {
            guard let rawValue = pendingValues[result[index].id],
                  let normalized = normalizedValue(rawValue) else { continue }
            result[index].timeSeconds = normalized
        }
        pendingValues.removeAll()
        return (result, [])
    }

    private func normalizedValue(_ rawValue: String) -> String? {
        if rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "" }
        guard let value = ExamReportParser.parseTime(rawValue), value >= 0 else { return nil }
        return String(value)
    }
}

private struct ExamTimeField: View {
    @Binding private var seconds: String
    @State private var text: String
    @FocusState private var isFocused: Bool
    let rowID: String
    let inputBuffer: ExamTimeInputBuffer
    let width: CGFloat

    init(seconds: Binding<String>, rowID: String, inputBuffer: ExamTimeInputBuffer, width: CGFloat) {
        _seconds = seconds
        _text = State(initialValue: Self.displayValue(seconds.wrappedValue))
        self.rowID = rowID
        self.inputBuffer = inputBuffer
        self.width = width
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { text },
            set: { value in
                text = value
                inputBuffer.stage(rowID: rowID, rawValue: value)
            }
        )
    }

    var body: some View {
        TextField("分:秒", text: textBinding)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .textFieldStyle(ErrorFormTextFieldStyle())
            .frame(width: width)
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if !focused { commitPendingValue() }
            }
            .onChange(of: seconds) { _, value in
                if !isFocused && !inputBuffer.hasPendingValue(for: rowID) {
                    text = Self.displayValue(value)
                }
            }
    }

    private func commitPendingValue() {
        guard let value = inputBuffer.commit(rowID: rowID) else { return }
        seconds = value
        text = Self.displayValue(value)
    }

    private static func displayValue(_ value: String) -> String {
        guard let seconds = Int(value), seconds >= 0 else { return value }
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
}

private struct ExamDerivedMetricsSummary: View {
    let metricsState: ExamModuleMetricsState

    var body: some View {
        let value = metricsState.metrics
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                metricText("题数", value.totalQuestions.map(String.init) ?? "—")
                metricText("答对", value.correctCount.map(String.init) ?? "—")
                metricText("答错", value.wrongCount.map(String.init) ?? "—")
                metricText("加权正确率", value.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "—")
                metricText("总用时", value.totalTimeSeconds.map { examFormatDuration(seconds: $0) } ?? "—")
            }
            if !value.conflictModules.isEmpty {
                Text("以下模块存在互相矛盾的重复数据，请核对：\(value.conflictModules.sorted().joined(separator: "、"))")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.warning)
            }
            ForEach(value.hierarchyWarnings, id: \.self) { warning in
                Text(warning + "，请人工核对；统计仍只取总项，不重复累计子项。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.warning)
            }
        }
        .padding(.top, 4)
    }

    private func metricText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(.system(size: 8))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExamLinkedErrorsSection: View {
    @Query private var records: [StoredRecord]
    let draft: ExamDraft
    let metricsState: ExamModuleMetricsState
    @State private var classificationCache = LibraryReviewSourceClassificationCache()
    @State private var projection = ExamLinkedErrorProjection()

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    ExamEditorSectionTitle(title: "关联错题")
                    Spacer()
                    Text("已关联 \(projection.linkedCount) 条 · 本次做错 \(metricsState.metrics.wrongCount.map(String.init) ?? "未知") 题")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                if draft.examType != .mock {
                    Text("仅模拟卷可从本次记录直接添加关联错题；正确题数和错题记录数分别统计。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                if projection.candidates.isEmpty {
                    Text("当前来源下暂无可关联错题")
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(projection.candidates) { error in
                        Button { toggleError(error.id) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: draft.linkedErrorIDs.contains(error.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(draft.linkedErrorIDs.contains(error.id) ? AppTheme.accent : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(error.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(1)
                                    Text([error.subject, error.module].compactMap { $0 }.joined(separator: " · "))
                                        .font(AppTheme.auxiliaryFont)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .onAppear(perform: refreshProjection)
        .onChange(of: draft.examType) { _, _ in refreshProjection() }
        .onChange(of: draft.id) { _, _ in refreshProjection() }
        .onChange(of: recordRevision) { _, _ in refreshProjection() }
    }

    private var recordRevision: [ExamEditorRecordRevision] {
        records
            .filter { $0.collection == "errors" || $0.collection == "exams" }
            .map(ExamEditorRecordRevision.init)
            .sorted { $0.compoundID < $1.compoundID }
    }

    private func refreshProjection() {
        let started = ProcessInfo.processInfo.systemUptime
        let errorRecords = records.filter { $0.collection == "errors" }
        let classifications = classificationCache.classifications(for: records)
        let candidates = errorRecords
            .filter { classifications[$0.compoundID] == draft.examType }
            .sorted {
                ($0.createdAt ?? $0.updatedAt ?? .distantPast)
                    > ($1.createdAt ?? $1.updatedAt ?? .distantPast)
            }
            .prefix(100)
            .map {
                ExamLinkedErrorCandidate(
                    id: $0.recordID,
                    title: $0.title,
                    subject: $0.subject,
                    module: $0.module
                )
            }
        let linkedCount = errorRecords.filter {
            $0.reviewSourceMetadata["sourceExamId"] as? String == draft.id
        }.count
        projection = ExamLinkedErrorProjection(candidates: Array(candidates), linkedCount: linkedCount)
        LibraryPerformanceLog.markIfSlow("exam.editor.linked-error-projection", since: started)
    }

    private func toggleError(_ id: String) {
        if draft.linkedErrorIDs.contains(id) { draft.linkedErrorIDs.remove(id) }
        else { draft.linkedErrorIDs.insert(id) }
    }
}

private struct ExamEditorRecordRevision: Equatable {
    let identity: ObjectIdentifier
    let compoundID: String
    let updatedAt: Date?
    let payloadCount: Int
    let indexPayloadCount: Int

    init(_ record: StoredRecord) {
        identity = ObjectIdentifier(record)
        compoundID = record.compoundID
        updatedAt = record.updatedAt
        payloadCount = record.payload.count
        indexPayloadCount = record.indexPayload?.count ?? 0
    }
}

private struct ExamLinkedErrorCandidate: Identifiable {
    let id: String
    let title: String
    let subject: String?
    let module: String?
}

private struct ExamLinkedErrorProjection {
    var candidates: [ExamLinkedErrorCandidate] = []
    var linkedCount = 0
}

private struct ExamReviewNoteSection: View {
    @State private var html: String
    let documentID: String
    let sessionID: UUID
    let session: NativeRichTextEditorSession

    init(initialHTML: String, documentID: String, sessionID: UUID, session: NativeRichTextEditorSession) {
        _html = State(initialValue: initialHTML)
        self.documentID = documentID
        self.sessionID = sessionID
        self.session = session
    }

    var body: some View {
        ExamEditorCard {
            VStack(alignment: .leading, spacing: 8) {
                ExamEditorSectionTitle(title: "复盘笔记")
                NativeRichTextEditor(
                    html: $html,
                    minHeight: 140,
                    editorSession: session,
                    editorDocumentID: documentID,
                    editorSessionID: sessionID,
                    defersPhotoPickerToParent: false
                )
            }
        }
    }
}

private struct ExamReportParserSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var reportTextDraft = ""
    @State private var reportPreview: ExamReportParser.Result?
    @State private var parseMessage: String?
    @State private var showReplaceConfirmation = false
    let draft: ExamDraft
    let onSaveText: (String) -> Void
    let onApplyParsed: (String, ExamReportParser.Result, Bool) -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button {
                        if let clipboard = UIPasteboard.general.string, !clipboard.isEmpty {
                            reportTextDraft = clipboard
                            reportPreview = nil
                            parseMessage = nil
                        } else {
                            parseMessage = "剪贴板中没有可粘贴的文字。"
                        }
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())

                    Button {
                        reportTextDraft = ""
                        reportPreview = nil
                        parseMessage = nil
                    } label: {
                        Label("清空", systemImage: "trash")
                    }
                    .buttonStyle(NativeSecondaryButtonStyle())

                    Spacer()
                    Button(action: parseReportDraft) {
                        Label("解析", systemImage: "text.magnifyingglass")
                    }
                    .buttonStyle(NativePrimaryButtonStyle())
                    .disabled(reportTextDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                TextEditor(text: $reportTextDraft)
                    .modifier(NativeDirectionalTextFieldNavigation())
                    .font(AppTheme.inputFont)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 190)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
                    .onChange(of: reportTextDraft) { _, _ in
                        reportPreview = nil
                        parseMessage = nil
                    }

                if let parseMessage {
                    Text(parseMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
                }
                if let reportPreview {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("识别到 \(reportPreview.lines.count) 项成绩")
                                .font(AppTheme.inputFont.weight(.semibold))
                            ForEach(reportPreview.lines) { line in
                                Text("\(line.subject) · \(line.totalQuestions) 题 · 答对 \(line.correctCount) · \(line.timeSeconds.isEmpty ? "用时未知" : examFormatDuration(seconds: Int(line.timeSeconds) ?? 0))")
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(reportPreview.duplicateConflicts, id: \.self) { subject in
                                Text("重复数据有冲突：\(subject)，请核对。")
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(AppTheme.warning)
                            }
                            ForEach(reportPreview.warnings, id: \.self) { warning in
                                Text(warning).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
                            }
                            if !reportPreview.unparsedLines.isEmpty {
                                Text("未识别 \(reportPreview.unparsedLines.count) 行，原文会保留：\(reportPreview.unparsedLines.prefix(6).joined(separator: "；"))")
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 180)
                }

                Spacer(minLength: 0)
                if let reportPreview, !reportPreview.lines.isEmpty {
                    if draft.moduleResults.isEmpty {
                        VStack(spacing: 7) {
                            Button("载入解析结果") { saveParsedReport(replacing: true) }
                                .buttonStyle(NativePrimaryButtonStyle())
                            Button("仅保存原文", action: saveReportTextOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 7) {
                            HStack {
                                Button("合并空缺字段") { saveParsedReport(replacing: false) }
                                    .buttonStyle(NativeSecondaryButtonStyle())
                                    .frame(maxWidth: .infinity)
                                Button("替换现有明细", role: .destructive) {
                                    showReplaceConfirmation = true
                                }
                                .buttonStyle(NativeDangerButtonStyle())
                                .frame(maxWidth: .infinity)
                            }
                            Button("仅保存原文", action: saveReportTextOnly)
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    Button("仅保存原文", action: saveReportTextOnly)
                        .buttonStyle(NativePrimaryButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(16)
            .background(AppTheme.groupedBackground)
            .navigationTitle("成绩报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .confirmationDialog("替换现有成绩明细？", isPresented: $showReplaceConfirmation, titleVisibility: .visible) {
                Button("替换明细", role: .destructive) { saveParsedReport(replacing: true) }
                Button("取消", role: .cancel) {}
            } message: {
                Text("替换会覆盖当前编辑中的明细；合并只补空字段。成绩记录尚未保存到数据库。")
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { reportTextDraft = draft.rawReport }
    }

    private func parseReportDraft() {
        let result = ExamReportParser.parse(reportTextDraft)
        reportPreview = result
        if result.lines.isEmpty {
            parseMessage = result.unparsedLines.isEmpty
                ? "没有解析出可识别的成绩行。原文不会丢失。"
                : "没有识别到成绩。未识别内容会保留：\(result.unparsedLines.prefix(3).joined(separator: "；"))"
        } else {
            parseMessage = nil
        }
    }

    private func saveReportTextOnly() {
        onSaveText(reportTextDraft)
        dismiss()
    }

    private func saveParsedReport(replacing: Bool) {
        guard let reportPreview, !reportPreview.lines.isEmpty else { return }
        onApplyParsed(reportTextDraft, reportPreview, replacing)
        dismiss()
    }
}

private struct ExamEditorCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8)
            )
    }
}

private struct ExamEditorSectionTitle: View {
    let title: String

    var body: some View {
        Text(title).font(.system(size: 13, weight: .medium))
    }
}

private struct ExamEditorFieldLabel: View {
    let title: String

    var body: some View {
        Text(title).font(.system(size: 11, weight: .regular)).foregroundStyle(.secondary)
    }
}

private func examFormatDuration(seconds: Int) -> String {
    if seconds >= 3_600 { return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分" }
    if seconds >= 60 { return "\(seconds / 60)分\(seconds % 60)秒" }
    return "\(seconds)秒"
}
