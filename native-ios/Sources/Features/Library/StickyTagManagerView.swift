import SwiftData
import SwiftUI

private struct StickyTagEditorState: Identifiable {
    let id = UUID()
    let original: StickyTagDefinition?
}

struct StickyTagManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var managesHome = true
    @State private var subject = SubjectDefinition.all[0]
    @State private var module = SubjectDefinition.all[0].modules[0]
    @State private var editor: StickyTagEditorState?
    @State private var draftName = ""
    @State private var draftColor = StickyTagRepository.colors[0]
    @State private var deleting: StickyTagDefinition?

    private var contextSubject: String { managesHome ? "" : subject.name }
    private var contextModule: String { managesHome || subject.isFlat ? "" : module }
    private var tags: [StickyTagDefinition] {
        StickyTagRepository.tags(
            subject: contextSubject,
            module: contextModule,
            records: records,
            includeDisabled: true
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("首页与学习库各模块拥有独立的便签标签。删除标签不会删除便签，原内容会归入无标签范围。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                Picker("标签范围", selection: $managesHome) {
                    Text("首页").tag(true)
                    Text("学习库").tag(false)
                }
                .pickerStyle(.segmented)
                if !managesHome { contextSelectors }
                HStack {
                    Text(contextTitle).font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { beginEdit(nil) } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }
                tagList
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("便签标签")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if editor != nil { editorDialog }
            if let deleting {
                NativeDeleteDialog(
                    title: "删除便签标签",
                    message: "确定删除“\(deleting.name)”？所属便签不会删除，将改为无标签。",
                    onDelete: { remove(deleting) },
                    onCancel: { self.deleting = nil }
                )
            }
        }
    }

    private var contextTitle: String {
        managesHome ? "首页便签" : "\(subject.name) · \(subject.isFlat ? "全部" : module)"
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

    private var tagList: some View {
        VStack(spacing: 0) {
            if tags.isEmpty {
                NativeStatusCard(title: "还没有标签", detail: "点击右上角新增当前范围的第一个便签标签", systemImage: "tag", color: .secondary)
            } else {
                ForEach(Array(tags.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 10) {
                        Circle().fill(Color(homeHex: item.color)).frame(width: 10, height: 10)
                        Text(item.name).font(AppTheme.bodyFont).foregroundStyle(item.enabled ? .primary : .secondary)
                        if !item.enabled { Text("已停用").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                        Spacer()
                        Button { move(item, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                        Button { move(item, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == tags.count - 1)
                        Button { toggle(item) } label: { Image(systemName: item.enabled ? "pause.circle" : "play.circle") }
                        Button { beginEdit(item) } label: { Image(systemName: "pencil") }
                        Button { deleting = item } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(minHeight: 46)
                    if index < tags.count - 1 { Divider() }
                }
            }
        }
        .padding(.horizontal, tags.isEmpty ? 0 : 14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editor?.original == nil ? "新增便签标签" : "修改便签标签",
            canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editor = nil },
            onSave: saveEditor
        ) {
            TextField("标签名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
            HStack(spacing: 12) {
                ForEach(StickyTagRepository.colors, id: \.self) { color in
                    Button { draftColor = color } label: {
                        Circle().fill(Color(homeHex: color)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(draftColor == color ? Color.primary : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
            Text("保存范围：\(contextTitle)").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private func selector(title: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                Text(value).font(AppTheme.inputFont).foregroundStyle(.primary)
            }
            Spacer()
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func beginEdit(_ item: StickyTagDefinition?) {
        draftName = item?.name ?? ""
        draftColor = item?.color ?? StickyTagRepository.colors[0]
        editor = StickyTagEditorState(original: item)
    }

    private func saveEditor() {
        guard let editor else { return }
        if let original = editor.original {
            try? StickyTagRepository.rename(original.name, to: draftName, color: draftColor, subject: contextSubject, module: contextModule, records: records, context: modelContext)
        } else {
            try? StickyTagRepository.add(draftName, color: draftColor, subject: contextSubject, module: contextModule, records: records, context: modelContext)
        }
        self.editor = nil
    }

    private func move(_ item: StickyTagDefinition, _ offset: Int) {
        try? StickyTagRepository.move(item.name, offset: offset, subject: contextSubject, module: contextModule, records: records, context: modelContext)
    }

    private func toggle(_ item: StickyTagDefinition) {
        try? StickyTagRepository.setEnabled(item.name, enabled: !item.enabled, subject: contextSubject, module: contextModule, records: records, context: modelContext)
    }

    private func remove(_ item: StickyTagDefinition) {
        try? StickyTagRepository.delete(item.name, subject: contextSubject, module: contextModule, records: records, context: modelContext)
        deleting = nil
    }
}
