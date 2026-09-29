import SwiftData
import SwiftUI

private struct QuantityQuestionTypeEditor: Identifiable {
    let id = UUID()
    let original: String?
}

struct QuantityQuestionTypeManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var editor: QuantityQuestionTypeEditor?
    @State private var draftName = ""
    @State private var deletingName: String?

    private var questionTypes: [String] {
        QuantityQuestionTypeRepository.types(records: records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里管理数量关系错题的题型。新建与编辑错题时的题型选择器会同步使用这份列表。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("数量题型").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }

                if questionTypes.isEmpty {
                    NativeStatusCard(title: "暂无数量题型", detail: "点击新增建立第一项", systemImage: "square.stack.3d.up", color: AppTheme.accent)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(questionTypes.enumerated()), id: \.element) { index, name in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                Text(name).font(AppTheme.bodyFont)
                                Spacer()
                                Button { move(name, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                                Button { move(name, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == questionTypes.count - 1)
                                Button { beginEdit(name) } label: { Image(systemName: "pencil") }
                                Button { deletingName = name } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(minHeight: 44)
                            if index < questionTypes.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("数量题型管理")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if editor != nil { editorDialog }
            if let deletingName {
                NativeDeleteDialog(
                    title: "删除数量题型",
                    message: "确定删除“\(deletingName)”？已有数量关系题目将改为未分类，相关考点分类也会移除。",
                    onDelete: { remove(deletingName) },
                    onCancel: { self.deletingName = nil }
                )
            }
        }
    }

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editor?.original == nil ? "新增数量题型" : "修改数量题型",
            canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editor = nil },
            onSave: saveEditor
        ) {
            TextField("题型名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
        }
    }

    private func beginEdit(_ name: String?) {
        draftName = name ?? ""
        editor = QuantityQuestionTypeEditor(original: name)
    }

    private func saveEditor() {
        guard let editor else { return }
        if let original = editor.original {
            try? QuantityQuestionTypeRepository.rename(original, to: draftName, records: records, context: modelContext)
        } else {
            try? QuantityQuestionTypeRepository.add(draftName, records: records, context: modelContext)
        }
        self.editor = nil
    }

    private func move(_ name: String, _ direction: Int) {
        try? QuantityQuestionTypeRepository.move(name, direction: direction, records: records, context: modelContext)
    }

    private func remove(_ name: String) {
        try? QuantityQuestionTypeRepository.delete(name, records: records, context: modelContext)
        deletingName = nil
    }
}
