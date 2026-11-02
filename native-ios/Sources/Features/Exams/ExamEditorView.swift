import SwiftData
import SwiftUI
import UIKit

struct ExamEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let recordID: String?
    @State private var draft: ExamDraft
    @State private var showDelete = false
    @State private var showParseConfirmation = false
    @State private var pendingParsedLines: [ExamModuleResult] = []
    @State private var pendingParseConflicts: [String] = []
    @State private var pendingUnparsedLines: [String] = []
    @State private var parseMessage: String?
    @State private var reparseMessage: String?

    init(record: StoredRecord? = nil, preferredType: LibraryReviewSource? = nil) {
        recordID = record?.recordID
        var value = ExamDraft(record: record)
        if record == nil, let preferredType, preferredType != .pending { value.examType = preferredType }
        _draft = State(initialValue: value)
    }

    private var errorRecords: [StoredRecord] { records.filter { $0.collection == "errors" } }
    private var linkedErrorCount: Int { errorRecords.filter { $0.jsonObject?["sourceExamId"] as? String == draft.id }.count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                attemptInformation
                rawReportSection
                resultSection
                scoreSection
                linkedErrorsSection
                VStack(alignment: .leading, spacing: 8) {
                    NativeFieldLabel(title: "复盘笔记")
                    NativeRichTextEditor(html: $draft.reviewNote, minHeight: 140)
                }.nativeCard()
            }.padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(recordID == nil ? "记录套卷" : "编辑套卷")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if recordID != nil { ToolbarItem(placement: .bottomBar) { Button("删除", role: .destructive) { showDelete = true } } }
        }
        .confirmationDialog("删除本次考试记录", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: { Text("关联错题会保留，只解除与本次考试的关系。") }
        .alert("重新解析成绩", isPresented: $showParseConfirmation) {
            Button("替换现有明细", role: .destructive) { replaceWithParsedResults() }
            Button("合并空缺字段") { mergeParsedResults() }
            Button("取消", role: .cancel) { }
        } message: {
            Text("当前已有可编辑成绩明细。替换会覆盖现有字段；合并只补空字段，并保留已有手工修改。")
        }
    }

    private var attemptInformation: some View {
        VStack(alignment: .leading, spacing: 11) {
            NativeFieldLabel(title: "考试类型")
            Picker("考试类型", selection: $draft.examType) {
                Text("真题").tag(LibraryReviewSource.real)
                Text("模拟卷").tag(LibraryReviewSource.mock)
                if draft.examType == .pending { Text("未分类").tag(LibraryReviewSource.pending) }
            }
            .pickerStyle(.segmented)
            TextField("套卷名称", text: $draft.name).textFieldStyle(NativeTextFieldStyle())
            DatePicker("考试日期", selection: $draft.examDate, displayedComponents: .date).font(AppTheme.inputFont)
        }.nativeCard()
    }

    private var scoreSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            NativeFieldLabel(title: "实际得分")
            HStack(spacing: 8) {
                TextField("实际得分", text: $draft.score).keyboardType(.decimalPad).textFieldStyle(NativeTextFieldStyle())
                Text("/").foregroundStyle(.secondary)
                TextField("满分", text: $draft.maximumScore).keyboardType(.decimalPad).textFieldStyle(NativeTextFieldStyle())
            }
            Text("得分与正确率分别记录；正确率按有效题数加权计算。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }.nativeCard()
    }

    private var rawReportSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                NativeFieldLabel(title: "成绩报告原文")
                Spacer()
                Button(action: parseReport) { Label("解析", systemImage: "text.magnifyingglass").font(AppTheme.inputFont.weight(.semibold)) }
                    .buttonStyle(.plain)
                    .disabled(draft.rawReport.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextEditor(text: $draft.rawReport)
                .font(AppTheme.inputFont)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 140)
                .padding(7)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
            if let parseMessage {
                Text(parseMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
            if let reparseMessage {
                Text(reparseMessage).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
        }.nativeCard()
    }

    private var resultSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NativeFieldLabel(title: "可编辑的模块成绩")
                Spacer()
                Button { draft.moduleResults.append(ExamModuleResult(subject: "新模块")) } label: {
                    Label("手动添加", systemImage: "plus").font(AppTheme.auxiliaryFont.weight(.semibold))
                }.buttonStyle(.plain)
            }
            if draft.moduleResults.isEmpty {
                Text("解析后可修改各项；也可以直接手动添加。留空的字段会按未知处理，不按 0 统计。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 5) {
                    Text("模块")
                    Spacer(minLength: 4)
                    Text("总题数")
                    Text("答对")
                    Text("报告率")
                    Text("用时")
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                ForEach($draft.moduleResults) { $line in
                    resultRow(line: $line)
                }
            }
            derivedMetrics
        }.nativeCard()
    }

    private func resultRow(line: Binding<ExamModuleResult>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                TextField("模块", text: line.subject).font(.system(size: 12, weight: .semibold))
                    .textFieldStyle(NativeTextFieldStyle())
                Spacer(minLength: 2)
                Button { draft.moduleResults.removeAll { $0.id == line.wrappedValue.id } } label: {
                    Image(systemName: "trash").foregroundStyle(AppTheme.danger).font(.system(size: 12))
                }.buttonStyle(.plain).accessibilityLabel("删除\(line.wrappedValue.subject)")
            }
            HStack(spacing: 5) {
                compactResultField("总题数", text: line.totalQuestions, keyboard: .numberPad)
                compactResultField("答对", text: line.correctCount, keyboard: .numberPad)
                compactResultField("报告率", text: line.reportedAccuracy, keyboard: .decimalPad, suffix: "%")
                timeField(line.timeSeconds)
            }
            Text("汇总归属：\(line.wrappedValue.parentSubject)")
                .font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .padding(8)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .onChange(of: line.wrappedValue.subject) { _, value in
            line.wrappedValue.parentSubject = ExamReportParser.parentSubject(for: value)
        }
    }

    private func compactResultField(_ title: String, text: Binding<String>, keyboard: UIKeyboardType, suffix: String = "") -> some View {
        HStack(spacing: 1) {
            TextField(title, text: text).keyboardType(keyboard).multilineTextAlignment(.center)
                .font(.system(size: 11, weight: .medium)).textFieldStyle(.plain)
            if !suffix.isEmpty { Text(suffix).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity).frame(height: 34)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
        .accessibilityLabel(title)
    }

    private func timeField(_ seconds: Binding<String>) -> some View {
        ExamTimeField(seconds: seconds)
    }

    private var derivedMetrics: some View {
        let value = draft.metrics
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                metricText("题数", value.totalQuestions.map(String.init) ?? "—")
                metricText("答对", value.correctCount.map(String.init) ?? "—")
                metricText("答错", value.wrongCount.map(String.init) ?? "—")
                metricText("加权正确率", value.accuracyPercent.map { String(format: "%.2f%%", $0) } ?? "—")
                metricText("总用时", value.totalTimeSeconds.map { formatDuration(seconds: $0) } ?? "—")
            }
            if !value.conflictModules.isEmpty {
                Text("以下模块存在互相矛盾的重复数据，请核对：\(value.conflictModules.sorted().joined(separator: "、"))")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
            ForEach(value.hierarchyWarnings, id: \.self) { warning in
                Text(warning + "，请人工核对；统计仍只取总项，不重复累计子项。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.warning)
            }
        }
        .padding(.top, 4)
    }

    private func metricText(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.7)
            Text(title).font(.system(size: 8)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var linkedErrorsSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                NativeFieldLabel(title: "关联错题")
                Spacer()
                Text("已关联 \(linkedErrorCount) 条 · 本次做错 \(draft.metrics.wrongCount.map(String.init) ?? "未知") 题")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            if draft.examType != .mock {
                Text("仅模拟卷可从本次记录直接添加关联错题；正确题数和错题记录数分别统计。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
            if candidateErrors.isEmpty {
                Text("当前来源下暂无可关联错题").font(AppTheme.bodyFont).foregroundStyle(.secondary)
            } else {
                ForEach(candidateErrors.prefix(100), id: \.recordID) { error in
                    Button { toggleError(error.recordID) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: draft.linkedErrorIDs.contains(error.recordID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(draft.linkedErrorIDs.contains(error.recordID) ? AppTheme.accent : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(error.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(1)
                                Text([error.subject, error.module].compactMap { $0 }.joined(separator: " · "))
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }.buttonStyle(.plain)
                }
            }
        }.nativeCard()
    }

    private var candidateErrors: [StoredRecord] {
        errorRecords.filter { LibraryReviewSource.classify($0, records: records) == draft.examType }
            .sorted { ($0.createdAt ?? $0.updatedAt ?? .distantPast) > ($1.createdAt ?? $1.updatedAt ?? .distantPast) }
    }

    private func parseReport() {
        let result = ExamReportParser.parse(draft.rawReport)
        guard !result.lines.isEmpty else {
            parseMessage = result.unparsedLines.isEmpty ? "没有解析出可识别的成绩行" : "未识别：\(result.unparsedLines.prefix(2).joined(separator: "；"))"
            return
        }
        pendingParsedLines = result.lines
        pendingParseConflicts = result.duplicateConflicts
        pendingUnparsedLines = result.unparsedLines
        parseMessage = nil
        reparseMessage = nil
        if draft.moduleResults.isEmpty {
            replaceWithParsedResults()
        } else {
            showParseConfirmation = true
        }
    }

    private func replaceWithParsedResults() {
        draft.moduleResults = pendingParsedLines
        reportParseOutcome(mergedCount: 0)
    }

    private func mergeParsedResults() {
        var conflicts = pendingParseConflicts
        for parsed in pendingParsedLines {
            let matches = draft.moduleResults.indices.filter { draft.moduleResults[$0].subject == parsed.subject }
            guard matches.count == 1, let index = matches.first else {
                if matches.isEmpty { draft.moduleResults.append(parsed) }
                else { conflicts.append(parsed.subject) }
                continue
            }
            var current = draft.moduleResults[index]
            for (old, fresh, label) in [
                (current.totalQuestions, parsed.totalQuestions, "总题数"),
                (current.correctCount, parsed.correctCount, "答对数"),
                (current.reportedAccuracy, parsed.reportedAccuracy, "正确率"),
                (current.timeSeconds, parsed.timeSeconds, "用时")
            ] where !old.isEmpty && old != fresh {
                conflicts.append("\(parsed.subject)\(label)")
            }
            if current.totalQuestions.isEmpty { current.totalQuestions = parsed.totalQuestions }
            if current.correctCount.isEmpty { current.correctCount = parsed.correctCount }
            if current.reportedAccuracy.isEmpty { current.reportedAccuracy = parsed.reportedAccuracy }
            if current.timeSeconds.isEmpty { current.timeSeconds = parsed.timeSeconds }
            draft.moduleResults[index] = current
        }
        pendingParseConflicts = Array(Set(conflicts)).sorted()
        reportParseOutcome(mergedCount: pendingParsedLines.count)
    }

    private func reportParseOutcome(mergedCount: Int) {
        var parts: [String] = []
        if !pendingParseConflicts.isEmpty { parts.append("重复或冲突项：\(pendingParseConflicts.joined(separator: "、"))，请检查") }
        if !pendingUnparsedLines.isEmpty { parts.append("未识别 \(pendingUnparsedLines.count) 行，原文已保留") }
        if parts.isEmpty { reparseMessage = "已载入 \(draft.moduleResults.count) 项成绩，可逐项核对。" }
        else { reparseMessage = parts.joined(separator: "；") }
        if mergedCount > 0, parts.isEmpty { reparseMessage = "已合并空缺字段，原有手工内容保留。" }
    }

    private func toggleError(_ id: String) {
        if draft.linkedErrorIDs.contains(id) { draft.linkedErrorIDs.remove(id) }
        else { draft.linkedErrorIDs.insert(id) }
    }

    private func save() {
        do { _ = try ExamRepository.save(draft, records: records, context: modelContext); dismiss() }
        catch { parseMessage = "保存失败：\(error.localizedDescription)" }
    }

    private func remove() {
        guard let recordID else { return }
        do { try ExamRepository.remove(id: recordID, records: records, context: modelContext); dismiss() }
        catch { parseMessage = "删除失败：\(error.localizedDescription)" }
    }

    private func formatDuration(seconds: Int) -> String {
        if seconds >= 3_600 { return "\(seconds / 3_600)小时\((seconds % 3_600) / 60)分" }
        if seconds >= 60 { return "\(seconds / 60)分\(seconds % 60)秒" }
        return "\(seconds)秒"
    }
}

private struct ExamTimeField: View {
    @Binding private var seconds: String
    @State private var text: String
    @FocusState private var isFocused: Bool

    init(seconds: Binding<String>) {
        _seconds = seconds
        _text = State(initialValue: Self.displayValue(seconds.wrappedValue))
    }

    var body: some View {
        TextField("分:秒", text: $text)
            .keyboardType(.numbersAndPunctuation)
            .multilineTextAlignment(.center)
            .font(.system(size: 11, weight: .medium))
            .textFieldStyle(.plain)
            .focused($isFocused)
            .frame(maxWidth: .infinity).frame(height: 34)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 7))
            .accessibilityLabel("用时，分:秒；超过一小时可输入时:分:秒")
            .onChange(of: text) { _, value in
                if value.isEmpty {
                    seconds = ""
                } else if let parsed = ExamReportParser.parseTime(value) {
                    seconds = String(parsed)
                }
            }
            .onChange(of: seconds) { _, value in
                guard !isFocused else { return }
                if let parsed = ExamReportParser.parseTime(text), String(parsed) == value { return }
                text = Self.displayValue(value)
            }
            .onChange(of: isFocused) { _, focused in
                guard !focused else { return }
                if text.isEmpty {
                    seconds = ""
                } else if let parsed = ExamReportParser.parseTime(text) {
                    seconds = String(parsed)
                    text = Self.displayValue(String(parsed))
                } else {
                    text = Self.displayValue(seconds)
                }
            }
    }

    private static func displayValue(_ rawValue: String) -> String {
        guard let value = Int(rawValue), value >= 0 else { return rawValue }
        if value >= 3_600 { return String(format: "%d:%02d:%02d", value / 3_600, (value % 3_600) / 60, value % 60) }
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}
