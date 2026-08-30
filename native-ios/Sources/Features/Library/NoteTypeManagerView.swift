import SwiftData
import SwiftUI

private struct NoteTypeEditorState: Identifiable {
    let id = UUID()
    let original: NoteTypeDefinition?
}

struct NoteTypeManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var subject = SubjectDefinition.all[0]
    @State private var module = SubjectDefinition.all[0].modules[0]
    @State private var editor: NoteTypeEditorState?
    @State private var draftName = ""
    @State private var draftColor = NoteTypeRepository.colors[0]
    @State private var deleting: NoteTypeDefinition?

    private var types: [NoteTypeDefinition] {
        NoteTypeRepository.types(subject: subject.name, module: contextModule, records: records, includeDisabled: true)
    }
    private var contextModule: String { subject.isFlat ? "" : module }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("每个模块拥有独立的笔记标签。删除标签后，原笔记仍保留并自动归入“全部”。")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                contextSelectors
                HStack {
                    Text("\(subject.name) · \(subject.isFlat ? "全部" : module)").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }
                typeList
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("笔记类型")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if editor != nil { editorDialog }
            if let deleting {
                NativeDeleteDialog(
                    title: "删除笔记标签",
                    message: "确定删除“\(deleting.name)”？所属笔记不会删除，将统一显示在“全部”中。",
                    onDelete: { remove(deleting) },
                    onCancel: { self.deleting = nil }
                )
            }
        }
    }

    private var contextSelectors: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SubjectDefinition.all) { value in
                    Button(value.name) { subject = value; module = value.modules.first ?? "" }
                }
            } label: { selector(title: "科目", value: subject.name) }
            if !subject.isFlat {
                Menu {
                    ForEach(subject.modules, id: \.self) { value in Button(value) { module = value } }
                } label: { selector(title: "模块", value: module) }
            }
        }
    }

    private var typeList: some View {
        VStack(spacing: 0) {
            ForEach(Array(types.enumerated()), id: \.element.id) { index, item in
                HStack(spacing: 10) {
                    Circle().fill(Color(homeHex: item.color)).frame(width: 10, height: 10)
                    Text(item.name).font(AppTheme.bodyFont).foregroundStyle(item.enabled ? .primary : .secondary)
                    if !item.enabled { Text("已停用").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                    Spacer()
                    Button { move(item, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                    Button { move(item, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == types.count - 1)
                    Button { toggle(item) } label: { Image(systemName: item.enabled ? "pause.circle" : "play.circle") }
                    Button { beginEdit(item) } label: { Image(systemName: "pencil") }
                    Button { deleting = item } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                }
                .font(.system(size: 12, weight: .medium))
                .frame(minHeight: 46)
                if index < types.count - 1 { Divider() }
            }
        }
        .padding(.horizontal, 14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editor?.original == nil ? "新增笔记标签" : "修改笔记标签",
            canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editor = nil }, onSave: saveEditor
        ) {
            TextField("标签名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
            HStack(spacing: 12) {
                ForEach(NoteTypeRepository.colors, id: \.self) { color in
                    Button { draftColor = color } label: {
                        Circle().fill(Color(homeHex: color)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(draftColor == color ? Color.primary : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
            Text("保存范围：\(subject.name) → \(subject.isFlat ? "全部" : module)")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private func selector(title: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                Text(value).font(AppTheme.inputFont).foregroundStyle(.primary)
            }
            Spacer(); Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12).frame(maxWidth: .infinity, minHeight: 44)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func beginEdit(_ item: NoteTypeDefinition?) {
        draftName = item?.name ?? ""
        draftColor = item?.color ?? NoteTypeRepository.colors[0]
        editor = NoteTypeEditorState(original: item)
    }

    private func saveEditor() {
        guard let editor else { return }
        if let original = editor.original {
            try? NoteTypeRepository.rename(original.name, to: draftName, color: draftColor, subject: subject.name, module: contextModule, records: records, context: modelContext)
        } else {
            try? NoteTypeRepository.add(draftName, color: draftColor, subject: subject.name, module: contextModule, records: records, context: modelContext)
        }
        self.editor = nil
    }

    private func move(_ item: NoteTypeDefinition, _ offset: Int) {
        try? NoteTypeRepository.move(item.name, offset: offset, subject: subject.name, module: contextModule, records: records, context: modelContext)
    }
    private func toggle(_ item: NoteTypeDefinition) {
        try? NoteTypeRepository.setEnabled(item.name, enabled: !item.enabled, subject: subject.name, module: contextModule, records: records, context: modelContext)
    }
    private func remove(_ item: NoteTypeDefinition) {
        try? NoteTypeRepository.delete(item.name, subject: subject.name, module: contextModule, records: records, context: modelContext)
        deleting = nil
    }
}
