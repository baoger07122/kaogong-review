import SwiftData
import SwiftUI

private struct QuantityReminderEditor: Identifiable {
    let id = UUID()
    let original: String?
}

struct QuantityReminderManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var editor: QuantityReminderEditor?
    @State private var draftName = ""
    @State private var deletingName: String?

    private let module = "数量关系-弱项"
    private var reminders: [String] {
        TagLibraryRepository.tags(kind: .thinkingTrap, module: module, records: records)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("这里管理数量关系中的弱项标签。新建错题时新增的内容也会自动保存在这里。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)

                HStack {
                    Text("数量提醒").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }

                if reminders.isEmpty {
                    NativeStatusCard(title: "暂无数量提醒", detail: "点击新增建立第一项", systemImage: "exclamationmark.bubble", color: AppTheme.accent)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(reminders.enumerated()), id: \.element) { index, name in
                            HStack(spacing: 10) {
                                Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                Text(name).font(AppTheme.bodyFont)
                                Spacer()
                                Button { move(name, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                                Button { move(name, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == reminders.count - 1)
                                Button { beginEdit(name) } label: { Image(systemName: "pencil") }
                                Button { deletingName = name } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(minHeight: 44)
                            if index < reminders.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("数量提醒管理")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if editor != nil { editorDialog }
            if let deletingName {
                NativeDeleteDialog(
                    title: "删除数量提醒",
                    message: "确定删除“\(deletingName)”？已有数量关系题目中的引用也会一并移除。",
                    onDelete: { remove(deletingName) },
                    onCancel: { self.deletingName = nil }
                )
            }
        }
    }

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editor?.original == nil ? "新增数量提醒" : "修改数量提醒",
            canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editor = nil },
            onSave: saveEditor
        ) {
            TextField("提醒名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
        }
    }

    private func beginEdit(_ name: String?) {
        draftName = name ?? ""
        editor = QuantityReminderEditor(original: name)
    }

    private func saveEditor() {
        guard let editor else { return }
        if let original = editor.original {
            try? TagLibraryRepository.rename(original, to: draftName, kind: .thinkingTrap, module: module, records: records, context: modelContext)
        } else {
            try? TagLibraryRepository.add(draftName, kind: .thinkingTrap, module: module, records: records, context: modelContext)
        }
        self.editor = nil
    }

    private func move(_ name: String, _ direction: Int) {
        try? TagLibraryRepository.move(name, direction: direction, kind: .thinkingTrap, module: module, records: records, context: modelContext)
    }

    private func remove(_ name: String) {
        try? TagLibraryRepository.delete(name, kind: .thinkingTrap, module: module, records: records, context: modelContext)
        deletingName = nil
    }
}
