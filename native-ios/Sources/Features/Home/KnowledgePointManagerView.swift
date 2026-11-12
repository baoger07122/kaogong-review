import SwiftData
import SwiftUI

private struct TagEditorState: Identifiable {
    let id = UUID()
    let original: String?
}

struct KnowledgePointManagerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var subject = SubjectDefinition.all[0]
    @State private var module = SubjectDefinition.all[0].modules[0]
    @State private var kind: ManagedTagKind = .knowledgePoint
    @State private var editor: TagEditorState?
    @State private var draftName = ""
    @State private var deletingName: String?
    @State private var errorMessage: String?
    @State private var showsOrder = false

    private var tags: [String] { TagLibraryRepository.tags(kind: kind, module: module, records: records) }
    private var availableModules: [String] {
        subject.name == "数量关系" ? QuantityQuestionTypeRepository.types(records: records) : subject.modules
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("考点、错因和思维误区按当前科目与模块统一管理；录入错题时输入的新内容会自动加入这里，不再自动创建预设标签。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.danger)
                }

                HStack(spacing: 10) {
                    Menu {
                        ForEach(SubjectDefinition.all) { value in
                            Button(value.name) {
                                subject = value
                                module = value.name == "数量关系"
                                    ? (QuantityQuestionTypeRepository.types(records: records).first ?? "")
                                    : (value.modules.first ?? "")
                            }
                        }
                    } label: { selector(title: "科目", value: subject.name) }

                    Menu {
                        ForEach(availableModules, id: \.self) { value in Button(value) { module = value } }
                    } label: { selector(title: subject.name == "数量关系" ? "题型" : "模块", value: module) }
                }

                Picker("标签类型", selection: $kind) {
                    ForEach(ManagedTagKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("\(module) · \(kind.rawValue)").font(AppTheme.sectionTitleFont)
                    Spacer()
                    if kind == .knowledgePoint {
                        Button("调整顺序") { showsOrder = true }
                            .font(AppTheme.inputFont.weight(.semibold))
                    }
                    Button { beginAdd() } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }

                if tags.isEmpty {
                    NativeStatusCard(title: "暂无\(kind.rawValue)", detail: "点击新增建立当前模块的第一项", systemImage: "tag", color: AppTheme.accent)
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(tags.enumerated()), id: \.element) { index, name in
                            HStack(spacing: 10) {
                                if kind != .knowledgePoint {
                                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                }
                                Text(name).font(AppTheme.bodyFont)
                                Spacer()
                                if kind != .knowledgePoint {
                                    Button { move(name, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                                    Button { move(name, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == tags.count - 1)
                                }
                                Button { beginEdit(name) } label: { Image(systemName: "pencil") }
                                Button { deletingName = name } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(minHeight: 44)
                            if index < tags.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("错题标签管理")
        .navigationBarTitleDisplayMode(.inline)
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .overlay {
            if editor != nil { editorDialog }
            if let deletingName {
                NativeDeleteDialog(
                    title: "删除\(kind.rawValue)",
                    message: "确定删除“\(deletingName)”？相关错题和笔记中的引用也会一并移除。",
                    onDelete: { remove(deletingName) },
                    onCancel: { self.deletingName = nil }
                )
            }
        }
        .sheet(isPresented: $showsOrder) { KnowledgePointOrderView(module: module) }
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

    private var editorDialog: some View {
        NativeEditorDialog(
            title: editor?.original == nil ? "新增\(kind.rawValue)" : "修改\(kind.rawValue)",
            canSave: !draftName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { editor = nil },
            onSave: saveEditor
        ) {
            TextField("名称", text: $draftName).textFieldStyle(NativeTextFieldStyle())
            Text("保存范围：\(subject.name) → \(module)")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private func beginAdd() {
        errorMessage = nil
        draftName = ""
        editor = TagEditorState(original: nil)
    }

    private func beginEdit(_ name: String) {
        errorMessage = nil
        draftName = name
        editor = TagEditorState(original: name)
    }

    private func saveEditor() {
        guard let editor else { return }
        do {
            if let original = editor.original {
                try TagLibraryRepository.rename(original, to: draftName, kind: kind, module: module, records: records, context: modelContext)
            } else {
                try TagLibraryRepository.add(draftName, kind: kind, module: module, records: records, context: modelContext)
            }
            errorMessage = nil
            self.editor = nil
        } catch {
            errorMessage = "标签保存失败：\(error.localizedDescription)"
        }
    }

    private func move(_ name: String, _ direction: Int) {
        do {
            try TagLibraryRepository.move(name, direction: direction, kind: kind, module: module, records: records, context: modelContext)
            errorMessage = nil
        } catch {
            errorMessage = "标签排序保存失败：\(error.localizedDescription)"
        }
    }

    private func remove(_ name: String) {
        do {
            try TagLibraryRepository.delete(name, kind: kind, module: module, records: records, context: modelContext)
            errorMessage = nil
            deletingName = nil
        } catch {
            errorMessage = "删除标签失败：\(error.localizedDescription)"
        }
    }
}
