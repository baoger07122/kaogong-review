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
    @State private var errorMessage: String?

    private var questionTypes: [String] {
        QuantityQuestionTypeRepository.types(records: records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里管理数量关系的题型。新建与编辑错题时的题型选择器会同步使用这份列表。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("题型").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }

                if questionTypes.isEmpty {
                    NativeStatusCard(title: "暂无题型", detail: "点击新增建立第一项", systemImage: "square.stack.3d.up", color: AppTheme.accent)
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
        .navigationTitle("数量关系")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if editor != nil { editorDialog }
            if let deletingName {
                NativeDeleteDialog(
                    title: "删除数量题型",
                    message: "确定删除“\(deletingName)”？已有题目将改为未分类；考点分类会移除，错因标签及分组会保留并归到未分类。",
                    onDelete: { remove(deletingName) },
                    onCancel: { self.deletingName = nil }
                )
            }
        }
        .alert("未能保存数量题型", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
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
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            errorMessage = "题型名称不能为空。"
            return
        }
        let isUnchangedName = editor.original.map { $0 == name } ?? false
        guard isUnchangedName || !questionTypes.contains(name) else {
            errorMessage = "当前科目已有同名题型。"
            return
        }
        do {
            if let original = editor.original {
                try QuantityQuestionTypeRepository.rename(original, to: name, records: records, context: modelContext)
            } else {
                try QuantityQuestionTypeRepository.add(name, records: records, context: modelContext)
            }
            self.editor = nil
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func move(_ name: String, _ direction: Int) {
        do {
            try QuantityQuestionTypeRepository.move(name, direction: direction, records: records, context: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = "题型排序保存失败：\(error.localizedDescription)"
        }
    }

    private func remove(_ name: String) {
        do {
            try QuantityQuestionTypeRepository.delete(name, records: records, context: modelContext)
            deletingName = nil
            errorMessage = nil
        } catch {
            deletingName = nil
            errorMessage = "删除题型失败：\(error.localizedDescription)"
        }
    }
}
