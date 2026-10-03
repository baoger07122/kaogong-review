import Foundation
import SwiftData
import SwiftUI
import UIKit

private struct ShenlunAdaptationDraft {
    var values = ShenlunAdaptationValues()
    let legacyFields: [ShenlunLegacyPayloadField]
    let rawPayload: String

    init(record: StoredRecord) {
        let object = record.jsonObject ?? [:]
        values.questionType = Self.firstNonEmptyText(in: object, keys: ["module", "type"])
            ?? record.module
            ?? ""
        values.questionSource = Self.text(in: object, keys: ["questionSource", "source"]) ?? ""
        values.questionNumber = Self.text(in: object, keys: ["questionNumber"]) ?? ""
        values.score = Self.text(in: object, keys: ["score"]) ?? ""
        values.totalScore = Self.text(in: object, keys: ["totalScore"]) ?? ""
        values.currentAffairsSupplement = Self.text(in: object, keys: ["currentAffairsSupplement"]) ?? ""
        values.myAnswer = Self.text(in: object, keys: ["myAnswer"]) ?? ""
        values.referenceAnswer = Self.text(in: object, keys: ["referenceAnswer"]) ?? ""
        values.myAnswerIssues = Self.text(in: object, keys: ["myAnswerIssues"]) ?? ""
        values.materialsAnalysis = Self.text(in: object, keys: ["materialsAnalysis"]) ?? ""
        values.reviewNote = Self.text(in: object, keys: ["note", "reviewNote"]) ?? ""
        values.materials = Self.stringArray(in: object, key: "materials")
        values.question = Self.text(in: object, keys: ["question", "title"]) ?? ""
        legacyFields = Self.makeLegacyFields(from: object)
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
           let string = String(data: data, encoding: .utf8) {
            rawPayload = string
        } else {
            rawPayload = "原始 payload 无法格式化，但会在适配前按字节保存。"
        }
    }

    private static func text(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }

    private static func firstNonEmptyText(in object: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = text(in: object, keys: [key]) else { continue }
            if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
        }
        return nil
    }

    private static func stringArray(in object: [String: Any], key: String) -> [String] {
        if let values = object[key] as? [String] { return values }
        if let values = object[key] as? [[String: Any]] {
            return values.compactMap { text(in: $0, keys: ["text", "content", "value"]) }
        }
        return []
    }

    private static func makeLegacyFields(from object: [String: Any]) -> [ShenlunLegacyPayloadField] {
        var fields: [ShenlunLegacyPayloadField] = []
        appendText("我的框架", key: "myFramework", object: object, to: &fields)
        appendText("参考框架", key: "stdFramework", object: object, to: &fields)
        appendText("逐段差距", key: "paragraph", object: object, to: &fields)

        if let rows = object["bias"] as? [[String: Any]] {
            let text = rows.enumerated().compactMap { index, row -> String? in
                let wrong = Self.text(in: row, keys: ["wrong"])
                let right = Self.text(in: row, keys: ["right"])
                guard wrong != nil || right != nil else { return nil }
                return [
                    "第 \(index + 1) 项",
                    wrong.map { "原思路：\($0)" },
                    right.map { "修正思路：\($0)" }
                ]
                .compactMap { $0 }
                .joined(separator: "\n")
            }
            if !text.isEmpty {
                fields.append(.init(title: "思维偏差", key: "bias", text: text.joined(separator: "\n\n")))
            }
        }

        appendList("错误的踩分点", key: "wrongList", object: object, to: &fields)
        appendList("遗漏的踩分点", key: "missedList", object: object, to: &fields)
        return fields
    }

    private static func appendText(
        _ title: String,
        key: String,
        object: [String: Any],
        to fields: inout [ShenlunLegacyPayloadField]
    ) {
        guard let text = text(in: object, keys: [key]), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        fields.append(.init(title: title, key: key, text: text))
    }

    private static func appendList(
        _ title: String,
        key: String,
        object: [String: Any],
        to fields: inout [ShenlunLegacyPayloadField]
    ) {
        guard let values = object[key] as? [String] else { return }
        let text = values
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { "• \($0)" }
            .joined(separator: "\n")
        if !text.isEmpty { fields.append(.init(title: title, key: key, text: text)) }
    }
}

private struct ShenlunLegacyPayloadField: Identifiable {
    let title: String
    let key: String
    let text: String
    var id: String { key }
}

struct ShenlunAdaptationView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShenlunAdaptationDraft
    @State private var isSaving = false
    @State private var errorMessage: String?

    let record: StoredRecord
    let onAdapted: () -> Void

    init(record: StoredRecord, onAdapted: @escaping () -> Void) {
        self.record = record
        self.onAdapted = onAdapted
        _draft = State(initialValue: ShenlunAdaptationDraft(record: record))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                noticeCard
                targetFields
                legacyFields
                rawPayloadDisclosure
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.danger)
                        .padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color.white)
        .navigationTitle("适配旧申论数据")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismissWithoutSaving() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(isSaving ? "适配中…" : "确认适配", action: adapt)
                    .disabled(isSaving)
            }
        }
    }

    private var noticeCard: some View {
        adaptationCard {
            Label("旧格式记录", systemImage: "arrow.triangle.2.circlepath")
                .font(AppTheme.cardTitleFont)
            Text("查看和修改以下目标字段不会改变原记录。点击“确认适配”后，应用会先保存一次原始 payload 快照，再在一个事务中写入规范字段和格式版本。")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var targetFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("当前目标字段")
                .font(AppTheme.sectionTitleFont)

            adaptationCard {
                Text("题型及来源").font(AppTheme.cardTitleFont)
                HStack(spacing: 8) {
                    TextField("题型 / 模块", text: $draft.values.questionType)
                        .textFieldStyle(NativeTextFieldStyle())
                    TextField("来源", text: $draft.values.questionSource)
                        .textFieldStyle(NativeTextFieldStyle())
                }
                HStack(spacing: 8) {
                    TextField("题号", text: $draft.values.questionNumber)
                        .keyboardType(.numberPad)
                        .textFieldStyle(NativeTextFieldStyle())
                    TextField("得分", text: $draft.values.score)
                        .keyboardType(.numberPad)
                        .textFieldStyle(NativeTextFieldStyle())
                    TextField("总分", text: $draft.values.totalScore)
                        .keyboardType(.numberPad)
                        .textFieldStyle(NativeTextFieldStyle())
                }
            }

            adaptationTextField("题干", text: $draft.values.question, minimumHeight: 82)
            adaptationTextField("时政补充", text: $draft.values.currentAffairsSupplement)
            adaptationTextField("我的作答", text: $draft.values.myAnswer, minimumHeight: 120)
            adaptationTextField("参考答案", text: $draft.values.referenceAnswer, minimumHeight: 120)
            adaptationTextField("我的作答问题", text: $draft.values.myAnswerIssues)
            adaptationTextField("材料分析", text: $draft.values.materialsAnalysis)
            adaptationTextField("复盘笔记", text: $draft.values.reviewNote)

            adaptationCard {
                HStack {
                    Text("材料数组").font(AppTheme.cardTitleFont)
                    Spacer()
                    Button { draft.values.materials.append("") } label: {
                        Label("增加材料", systemImage: "plus")
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                if draft.values.materials.isEmpty {
                    Text("可留空；原始材料不会因取消而改变。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(draft.values.materials.indices), id: \.self) { index in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                NativeFieldLabel(title: "材料 \(index + 1)")
                                Spacer()
                                Button("删除") { draft.values.materials.remove(at: index) }
                                    .font(AppTheme.auxiliaryFont)
                                    .foregroundStyle(AppTheme.danger)
                                    .buttonStyle(.plain)
                            }
                            adaptationTextEditor(text: materialBinding(index: index), height: 170)
                        }
                    }
                }
            }
        }
    }

    private var legacyFields: some View {
        adaptationCard {
            HStack {
                Text("旧字段原文").font(AppTheme.cardTitleFont)
                Spacer()
                Text("原样保留")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
            Text("以下内容不会被静默丢弃。目标字段可编辑；旧字段可以复制到复盘笔记、复制到系统剪贴板，或保留在原始字段中。")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
            if draft.legacyFields.isEmpty {
                Text("未发现旧版扩展字段")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(draft.legacyFields) { field in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(field.title).font(AppTheme.fieldLabelFont)
                            Text(field.key)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                            Spacer()
                            Button("复制") { UIPasteboard.general.string = field.text }
                                .font(AppTheme.auxiliaryFont)
                                .buttonStyle(.plain)
                            Button("并入复盘笔记") { appendToReview(field.text) }
                                .font(AppTheme.auxiliaryFont)
                                .foregroundStyle(AppTheme.accent)
                                .buttonStyle(.plain)
                        }
                        Text(field.text)
                            .font(AppTheme.inputFont)
                            .foregroundStyle(.secondary)
                            .lineSpacing(AppTheme.inputLineSpacing)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
            }
        }
    }

    private var rawPayloadDisclosure: some View {
        DisclosureGroup("原始 payload 快照（只读）") {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(draft.rawPayload)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(maxHeight: 260)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .font(AppTheme.cardTitleFont)
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
    }

    private func adaptationTextField(
        _ title: String,
        text: Binding<String>,
        minimumHeight: CGFloat = 82
    ) -> some View {
        adaptationCard {
            Text(title).font(AppTheme.cardTitleFont)
            adaptationTextEditor(text: text, height: minimumHeight)
        }
    }

    private func adaptationTextEditor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(AppTheme.inputFont)
            .lineSpacing(AppTheme.inputLineSpacing)
            .scrollContentBackground(.hidden)
            .frame(minHeight: height)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.primary.opacity(0.11), lineWidth: 0.8)
            }
    }

    private func materialBinding(index: Int) -> Binding<String> {
        Binding(
            get: { draft.values.materials.indices.contains(index) ? draft.values.materials[index] : "" },
            set: { value in
                guard draft.values.materials.indices.contains(index) else { return }
                draft.values.materials[index] = value
            }
        )
    }

    private func adaptationCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.10), lineWidth: 0.8)
        }
    }

    private func appendToReview(_ text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if draft.values.reviewNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            draft.values.reviewNote = text
        } else {
            draft.values.reviewNote += "\n\n" + text
        }
    }

    private func dismissWithoutSaving() {
        // No context mutation occurs on this path; the original payload remains
        // byte-for-byte unchanged.
        dismiss()
    }

    private func adapt() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil
        do {
            try LibraryRecordRepository.adaptShenlunRecord(
                record: record,
                values: draft.values,
                context: modelContext
            )
            isSaving = false
            onAdapted()
        } catch {
            isSaving = false
            errorMessage = "适配失败：\(error.localizedDescription)；原记录未修改。"
        }
    }

}
