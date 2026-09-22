import SwiftUI

struct LibraryNoteDetailView: View {
    let record: StoredRecord
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var showDelete = false

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var title: String {
        ["title", "name", "text"].compactMap { object[$0] as? String }.first(where: { !$0.isEmpty }) ?? "未命名笔记"
    }
    private var content: String {
        ["content", "note", "analysis"].compactMap { object[$0] as? String }.first ?? ""
    }
    private var type: String { object["type"] as? String ?? "" }
    private var knowledgePoint: String { object["knowledgePoint"] as? String ?? "" }
    private var quantityStructure: String { object["quantityStructure"] as? String ?? "" }
    private var weaknessTags: [String] { object["weaknessTags"] as? [String] ?? [] }
    private var isQuantityRelations: Bool { record.subject == "数量关系" }

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(title)
                        .font(.system(size: 24, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if !isQuantityRelations, !type.isEmpty || !knowledgePoint.isEmpty {
                        NativeTagFlow(spacing: 6) {
                            if !type.isEmpty { detailChip(type) }
                            if !knowledgePoint.isEmpty { detailChip(knowledgePoint) }
                        }
                    }
                    if isQuantityRelations {
                        detailLine("题型", QuantityQuestionTypeCatalog.displayName(for: record.module))
                        detailLine("题目结构", quantityStructure)
                        detailTags("考点", splitTags(knowledgePoint))
                        detailTags("弱项标签", weaknessTags)
                    }
                    if content.isEmpty {
                        Text("暂无正文")
                            .font(AppTheme.noteBodyFont)
                            .foregroundStyle(.tertiary)
                    } else {
                        NativeRichTextDisplay(html: content, minHeight: 80)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 18)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)

            if showDelete {
                NativeDeleteDialog(
                    title: "删除笔记",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
        .navigationTitle("笔记详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: onEdit) { Label("编辑笔记", systemImage: "pencil") }
                    Button(role: .destructive) { showDelete = true } label: { Label("删除笔记", systemImage: "trash") }
                } label: { Image(systemName: "ellipsis") }
            }
            .documentToolbarBackground()
        }
    }

    private func detailChip(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 9)
            .frame(height: 27)
            .background(AppTheme.accent.opacity(0.08), in: Capsule())
    }

    @ViewBuilder private func detailLine(_ label: String, _ value: String) -> some View {
        if !value.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text("\(label)：").font(.system(size: 13, weight: .medium))
                Text(value).font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private func detailTags(_ label: String, _ values: [String]) -> some View {
        if !values.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text("\(label)：").font(.system(size: 13, weight: .medium)).padding(.top, 4)
                NativeTagFlow(spacing: 5) {
                    ForEach(values, id: \.self) { detailChip($0) }
                }
            }
        }
    }

    private func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
