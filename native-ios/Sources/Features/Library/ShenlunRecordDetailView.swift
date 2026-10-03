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
                ShenlunRecordContent(record: record, noteSession: noteSession)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity)
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
                    Button(action: openDoodle) {
                        Image(systemName: "pencil.and.scribble")
                    }
                    .accessibilityLabel("涂鸦")
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
        guard noteSession.finish() else { return }
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
            drawingData: drawingData,
            legacyPreviewDataURL: legacyPreview,
            onSave: saveDrawing
        )
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

    init(record: StoredRecord, noteSession: LibraryInlineNoteSession? = nil) {
        self.record = record
        self.noteSession = noteSession
    }

    private var object: [String: Any] { record.jsonObject ?? [:] }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            metadataSection

            if let supplement = nonEmptyText(object["currentAffairsSupplement"]) {
                ShenlunTextSection(title: "时政补充", text: supplement)
            }
            if let myAnswer = nonEmptyText(object["myAnswer"]) {
                ShenlunTextSection(title: "我的作答", text: myAnswer)
            }
            if let referenceAnswer = nonEmptyText(object["referenceAnswer"]) {
                ShenlunTextSection(title: "参考答案", text: referenceAnswer)
            }
            if let issues = nonEmptyText(object["myAnswerIssues"]) {
                ShenlunTextSection(title: "我的作答问题", text: issues)
            }
            if let analysis = nonEmptyText(object["materialsAnalysis"]) {
                ShenlunTextSection(title: "材料分析", text: analysis)
            }

            if let noteSession {
                LibraryInlineNoteView(record: record, session: noteSession, title: "复盘笔记")
                    .padding(14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
                    }
            } else if let note = nonEmptyText(object["note"]) {
                ShenlunTextSection(title: "复盘笔记", text: note)
            }

            ForEach(legacyFields) { field in
                ShenlunTextSection(title: field.title, text: field.text, isLegacy: true)
            }

            ForEach(Array(materials.enumerated()), id: \.offset) { index, material in
                ShenlunTextSection(title: "材料 \(index + 1)", text: material)
            }

            if let question = nonEmptyText(object["question"]) ?? nonEmptyText(object["title"]) {
                ShenlunTextSection(title: "题干", text: question)
            }
        }
    }

    private var metadataSection: some View {
        ShenlunDetailCard(title: "题型及来源", systemImage: "doc.text") {
            let subject = nonEmptyText(object["subject"]) ?? record.subject ?? "申论"
            let module = nonEmptyText(object["module"])
                ?? record.module.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
            let classification = [subject, module].compactMap { $0 }.joined(separator: " · ")
            if !classification.isEmpty {
                Text(classification)
                    .font(AppTheme.bodyFont.weight(.medium))
                    .foregroundStyle(.primary)
            }

            let source = nonEmptyText(object["questionSource"]) ?? nonEmptyText(object["source"])
            let questionNumber = nonEmptyText(object["questionNumber"])
            if source != nil || questionNumber != nil {
                Text([source, questionNumber].compactMap { $0 }.joined(separator: "-"))
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
            }

            if let score = nonEmptyText(object["score"]) {
                let total = nonEmptyText(object["totalScore"])
                Text("得分：\(score)\(total.map { " / \($0)" } ?? "")")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var materials: [String] {
        (object["materials"] as? [String] ?? [])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
        let text = values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "• \($0)" }
            .joined(separator: "\n")
        if !text.isEmpty { fields.append(.init(title: title, text: text)) }
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
}

private struct ShenlunLegacyField: Identifiable {
    let title: String
    let text: String
    var id: String { title }
}

private struct ShenlunDetailCard<Content: View>: View {
    let title: String
    let systemImage: String?
    let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let systemImage {
                Label(title, systemImage: systemImage)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
            } else {
                Text(title)
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
            }
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
    }
}

private struct ShenlunTextSection: View {
    let title: String
    let text: String
    var isLegacy = false

    var body: some View {
        ShenlunDetailCard(title: title) {
            Text(text)
                .font(AppTheme.bodyFont)
                .foregroundStyle(isLegacy ? Color.secondary : Color.primary)
                .lineSpacing(4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
    }
}
