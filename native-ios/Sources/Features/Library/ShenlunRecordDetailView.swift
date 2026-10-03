import SwiftData
import SwiftUI

struct ShenlunRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    let record: StoredRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDelete = false
    @StateObject private var noteSession = LibraryInlineNoteSession()

    var body: some View {
        ZStack {
            ScrollView {
                ShenlunRecordContent(
                    record: record,
                    noteSession: record.requiresShenlunAdaptation ? nil : noteSession,
                    onAdaptation: onEdit
                )
                    .padding(.horizontal, 16)
                    .padding(.top, 5)
                    .padding(.bottom, 14)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity)
                    .overlay {
                        LibraryDoodleContentLayer(
                            session: doodleSession,
                            targetRecordID: record.compoundID
                        )
                    }
            }
            .background(Color.white)

            if showDelete {
                NativeDeleteDialog(
                    title: "删除申论复盘",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
        .navigationTitle("申论详情")
        .navigationBarTitleDisplayMode(.inline)
        .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button(action: record.requiresShenlunAdaptation ? onEdit : openDoodle) {
                        Image(systemName: "pencil.and.scribble")
                    }
                    .accessibilityLabel(record.requiresShenlunAdaptation ? "先适配旧数据" : "涂鸦")
                    Menu {
                        Button {
                            if noteSession.finish() { onEdit() }
                        } label: {
                            Label("编辑申论记录", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            if noteSession.finish() { showDelete = true }
                        } label: {
                            Label("删除申论记录", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            .documentToolbarBackground()
        }
    }

    private func openDoodle() {
        let openStart = ProcessInfo.processInfo.systemUptime
        let object = record.jsonObject ?? [:]
        let drawingData = (object["pencilKitData"] as? String)
            ?? (object["drawingData"] as? String)
            ?? ""
        let legacyPreview = drawingData.isEmpty
            ? ((object["drawingPreview"] as? String)
                ?? (object["doodle"] as? String)
                ?? (object["drawingDataURL"] as? String)
                ?? "")
            : ""
        doodleSession.present(
            targetRecordID: record.compoundID,
            drawingData: drawingData,
            legacyPreviewDataURL: legacyPreview,
            onSave: saveDrawing
        )
        LibraryPerformanceLog.mark("doodle.tap-to-present", since: openStart)
        Task { @MainActor in
            await Task.yield()
            _ = noteSession.finish()
        }
    }

    private func saveDrawing(_ drawingData: String, legacyPreviewCleared: Bool) -> String? {
        LibraryDoodlePersistence.save(
            record: record,
            context: modelContext,
            drawingData: drawingData,
            legacyPreviewCleared: legacyPreviewCleared
        )
    }
}

struct ShenlunRecordContent: View {
    let record: StoredRecord
    let noteSession: LibraryInlineNoteSession?
    let onAdaptation: (() -> Void)?

    init(
        record: StoredRecord,
        noteSession: LibraryInlineNoteSession? = nil,
        onAdaptation: (() -> Void)? = nil
    ) {
        self.record = record
        self.noteSession = noteSession
        self.onAdaptation = onAdaptation
    }

    private var object: [String: Any] { record.jsonObject ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            statusBadge
            sourceRow
            legacyAdaptationRow
            materialsBlock
            questionBlock
            answerComparison

            if let issues = nonEmptyText(object["myAnswerIssues"]) {
                plainSection(title: "我的作答问题", text: bulletized(issues))
            }
            if let analysis = nonEmptyText(object["materialsAnalysis"]) {
                plainSection(title: "材料分析", text: analysis)
            }
            if let supplement = nonEmptyText(object["currentAffairsSupplement"]) {
                plainSection(title: "时政补充", text: supplement)
            }
            noteBlock
            legacyBlock
            dateBlock
        }
    }

    @ViewBuilder private var statusBadge: some View {
        Text("错题")
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.danger)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(AppTheme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder private var sourceRow: some View {
        if let sourceText {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text("题目来源：")
                    .foregroundStyle(.secondary)
                Text(sourceText)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 12, weight: .regular))
        }
    }

    @ViewBuilder private var legacyAdaptationRow: some View {
        if record.requiresShenlunAdaptation {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("旧格式记录")
                    .font(AppTheme.auxiliaryFont.weight(.medium))
                Spacer(minLength: 8)
                if let onAdaptation {
                    Button("适配旧数据", action: onAdaptation)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.11))
                    .frame(height: 0.7)
            }
        }
    }

    @ViewBuilder private var materialsBlock: some View {
        ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
            readingBlock(title: "材料 \(index + 1)", text: material)
        }
    }

    @ViewBuilder private var questionBlock: some View {
        if let question = nonEmptyText(object["question"]) ?? nonEmptyText(object["title"]) {
            readingBlock(title: "题干", text: question)
        }
    }

    @ViewBuilder private var answerComparison: some View {
        let myAnswer = nonEmptyText(object["myAnswer"])
        let referenceAnswer = nonEmptyText(object["referenceAnswer"])
        if myAnswer != nil || referenceAnswer != nil {
            VStack(alignment: .leading, spacing: 10) {
                Text("作答对照")
                    .font(AppTheme.sectionTitleFont)
                if let myAnswer {
                    accentTextBlock(title: "我的作答", text: myAnswer, color: AppTheme.accent)
                }
                if let referenceAnswer {
                    accentTextBlock(title: "参考答案", text: referenceAnswer, color: AppTheme.success)
                }
            }
            .padding(.top, 4)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.11))
                    .frame(height: 0.7)
            }
        }
    }

    @ViewBuilder private var noteBlock: some View {
        if let noteSession {
            LibraryInlineNoteView(record: record, session: noteSession)
                .padding(.top, 4)
        } else if let note = nonEmptyText(object["note"]) {
            plainSection(title: "错题笔记", text: note)
        }
    }

    @ViewBuilder private var legacyBlock: some View {
        ForEach(legacyFields) { field in
            plainSection(title: field.title, text: field.text, isLegacy: true)
        }
    }

    @ViewBuilder private var dateBlock: some View {
        if record.createdAt != nil || record.updatedAt != nil {
            VStack(alignment: .leading, spacing: 4) {
                if let createdAt = record.createdAt {
                    Text("收录于 \(Self.dateFormatter.string(from: createdAt))")
                }
                if let updatedAt = record.updatedAt {
                    Text("上次更新 \(Self.dateFormatter.string(from: updatedAt))")
                }
            }
            .font(.system(size: 11, weight: .regular))
            .foregroundStyle(.tertiary)
            .padding(.top, 8)
        }
    }

    private func readingBlock(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.sectionTitleFont)
            readableText(
                text,
                color: .primary,
                font: AppTheme.questionTextFont,
                lineSpacing: AppTheme.questionLineSpacing
            )
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                }
        }
    }

    private func accentTextBlock(title: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(AppTheme.cardTitleFont)
                readableText(text, color: .primary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func plainSection(title: String, text: String, isLegacy: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.sectionTitleFont)
            readableText(text, color: isLegacy ? .secondary : .primary)
        }
        .padding(.top, 4)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.11))
                .frame(height: 0.7)
        }
    }

    @ViewBuilder private func readableText(
        _ value: String,
        color: Color,
        font: Font = AppTheme.bodyFont,
        lineSpacing: CGFloat = AppTheme.questionLineSpacing
    ) -> some View {
        if value.range(of: "<[^>]+>", options: .regularExpression) != nil {
            NativeRichTextDisplay(html: value, minHeight: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text(value)
                .font(font)
                .foregroundStyle(color)
                .lineSpacing(lineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }

    private var sourceText: String? {
        let source = nonEmptyText(object["questionSource"]) ?? nonEmptyText(object["source"])
        guard let source else { return nil }
        let questionNumber = nonEmptyText(object["questionNumber"])
        let value = [source, questionNumber].compactMap { $0 }.joined(separator: "-")
        return value.isEmpty ? nil : value
    }

    private var materials: [String] {
        if let values = object["materials"] as? [String] {
            return values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        }
        if let values = object["materials"] as? [[String: Any]] {
            return values.compactMap { nonEmptyText($0["text"] ?? $0["content"] ?? $0["value"]) }
        }
        return []
    }

    private var legacyFields: [ShenlunLegacyField] {
        var fields: [ShenlunLegacyField] = []
        appendLegacyText("我的框架", key: "myFramework", to: &fields)
        appendLegacyText("参考框架", key: "stdFramework", to: &fields)
        appendLegacyText("逐段差距", key: "paragraph", to: &fields)

        if let rows = object["bias"] as? [[String: Any]] {
            let text = rows.enumerated().compactMap { index, row -> String? in
                let wrong = nonEmptyText(row["wrong"])
                let right = nonEmptyText(row["right"])
                guard wrong != nil || right != nil else { return nil }
                return ["第 \(index + 1) 项", wrong.map { "原思路：\($0)" }, right.map { "修正思路：\($0)" }]
                    .compactMap { $0 }
                    .joined(separator: "\n")
            }
            if !text.isEmpty { fields.append(.init(title: "思维偏差", text: text.joined(separator: "\n\n"))) }
        }

        appendLegacyList("错误的踩分点", key: "wrongList", to: &fields)
        appendLegacyList("遗漏的踩分点", key: "missedList", to: &fields)
        return fields
    }

    private func appendLegacyText(_ title: String, key: String, to fields: inout [ShenlunLegacyField]) {
        guard let value = nonEmptyText(object[key]) else { return }
        fields.append(.init(title: title, text: value))
    }

    private func appendLegacyList(_ title: String, key: String, to fields: inout [ShenlunLegacyField]) {
        guard let values = object[key] as? [String] else { return }
        let text = values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "• \($0)" }
            .joined(separator: "\n")
        if !text.isEmpty { fields.append(.init(title: title, text: text)) }
    }

    private func bulletized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return "" }
                let clean = trimmed.replacingOccurrences(
                    of: "^(?:[•●▪·*-]|\\d+[.、、])\\s*",
                    with: "",
                    options: .regularExpression
                )
                return "• \(clean)"
            }
            .joined(separator: "\n")
    }

    private func nonEmptyText(_ value: Any?) -> String? {
        guard let value else { return nil }
        let text: String
        if let string = value as? String {
            text = string
        } else if let number = value as? NSNumber {
            text = number.stringValue
        } else {
            return nil
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : text
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()
}

private struct ShenlunLegacyField: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}
