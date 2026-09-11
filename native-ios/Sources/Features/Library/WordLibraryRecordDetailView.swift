import SwiftUI

struct WordLibraryRecordDetailView: View {
    let record: StoredRecord
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    @State private var showDelete = false

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var category: WordCategory {
        WordCategory(rawValue: text("category", "type")) ?? .idiomDefinition
    }
    private var entryKind: WordEntryKind {
        WordEntryKind(rawValue: text("entryKind")) ?? .word
    }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        detailTag(category.title, color: AppTheme.accent)
                        if !category.isComparison { detailTag(entryKind.title, color: .secondary) }
                        if !text("sentiment").isEmpty { detailTag(text("sentiment"), color: .secondary) }
                    }

                    Text(recordTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .textSelection(.enabled)

                    detailText("共同语义", value: text("commonMeaning"))
                    if category.isComparison { comparisonTerms }
                    detailText("核心区别", value: text("compareNote", "coreDifference"))

                    let explanation = category.isComparison ? text("judgmentHint") : text("meaning")
                    if !explanation.isEmpty {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(category.isComparison ? "判断提示" : "释义")
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                            NativeRichTextDisplay(html: explanation, minHeight: 34)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    detailText("拼音", value: text("pinyin"))
                    detailText("词性", value: text("pos", "partOfSpeech"))
                    detailText("例句", value: text("example"))
                    detailText("我的理解", value: text("myUnderstanding"))
                    detailText("常见搭配", value: text("collocations"))
                    detailText("来源", value: text("source"))
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)

            if showDelete, let onDelete {
                NativeDeleteDialog(
                    title: "删除词语记录",
                    message: "删除后将同时解除与错题的关联。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
        .navigationTitle("词语详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 10) {
                    if let onEdit {
                        Button(action: onEdit) {
                            Label("编辑", systemImage: "pencil")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .accessibilityLabel("编辑词语")
                    }
                    if onDelete != nil {
                        Menu {
                            Button(role: .destructive) { showDelete = true } label: {
                                Label("删除词语", systemImage: "trash")
                            }
                        } label: { Image(systemName: "ellipsis") }
                    }
                }
            }
            .documentToolbarBackground()
        }
    }

    private var comparisonTerms: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("辨析词语").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach(Array(compareTerms.enumerated()), id: \.offset) { _, term in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(term.name).font(.system(size: 16, weight: .semibold))
                        detailTag(term.kind.title, color: .secondary)
                    }
                    if !term.meaning.isEmpty {
                        NativeRichTextDisplay(html: term.meaning, minHeight: 24)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder private func detailText(_ label: String, value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
            }
        }
    }

    private func detailTag(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var recordTitle: String {
        let value = text("name", "words", "title")
        return value.isEmpty ? "未命名词语" : value
    }

    private struct Term {
        let name: String
        let meaning: String
        let kind: WordEntryKind
    }

    private var compareTerms: [Term] {
        guard let values = object["compareWords"] as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            let name = value["name"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            return Term(
                name: name,
                meaning: value["meaning"] as? String ?? "",
                kind: WordEntryKind(rawValue: value["entryKind"] as? String ?? "") ?? .word
            )
        }
    }

    private func text(_ keys: String...) -> String {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }
}
