import SwiftData
import SwiftUI

struct LibraryRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]

    let kind: LibraryContentKind
    let scope: LibraryScope
    let recordID: String?
    @State private var draft: LibraryRecordDraft
    @State private var showDelete = false

    init(kind: LibraryContentKind, scope: LibraryScope, record: StoredRecord? = nil) {
        self.kind = kind
        self.scope = scope
        recordID = record?.recordID
        _draft = State(initialValue: LibraryRecordDraft(kind: kind, scope: scope, record: record))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                contextCard
                switch kind {
                case .errors: errorFields
                case .notes: noteFields
                case .stickies: stickyFields
                case .words: wordFields
                }
            }
            .padding(20)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(recordID == nil ? "新增\(kind.rawValue)" : "编辑\(kind.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(!canSave)
            }
            if recordID != nil {
                ToolbarItem(placement: .bottomBar) {
                    Button("删除", role: .destructive) { showDelete = true }
                }
            }
        }
        .confirmationDialog("删除\(kind.rawValue)", isPresented: $showDelete, titleVisibility: .visible) {
            Button("删除", role: .destructive, action: remove)
            Button("取消", role: .cancel) {}
        } message: { Text("删除后无法在 App 内恢复。") }
    }

    private var contextCard: some View {
        VStack(spacing: 10) {
            Menu {
                ForEach(SubjectDefinition.all) { subject in
                    Button(subject.name) {
                        draft.subject = subject.name
                        draft.module = subject.modules.first ?? ""
                    }
                }
            } label: {
                NativePropertyRow(title: "科目", value: draft.subject, systemImage: "books.vertical") {}
                    .allowsHitTesting(false)
            }
            if let subject = SubjectDefinition.all.first(where: { $0.name == draft.subject }), !subject.modules.isEmpty {
                Menu {
                    ForEach(subject.modules, id: \.self) { module in Button(module) { draft.module = module } }
                } label: {
                    NativePropertyRow(title: "模块", value: draft.module, systemImage: "square.stack.3d.up") {}
                        .allowsHitTesting(false)
                }
            }
        }
        .nativeCard()
    }

    private var errorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeFieldLabel(title: "题目")
            editor(text: $draft.title, height: 100)
            NativeFieldLabel(title: "选项")
            ForEach(draft.options.indices, id: \.self) { index in
                TextField("选项 \(index + 1)", text: $draft.options[index]).textFieldStyle(NativeTextFieldStyle())
            }
            HStack {
                TextField("正确答案", text: $draft.correctOption).textFieldStyle(NativeTextFieldStyle())
                TextField("我的答案", text: $draft.userOption).textFieldStyle(NativeTextFieldStyle())
            }
            TextField("考点", text: $draft.knowledgePoint).textFieldStyle(NativeTextFieldStyle())
            TextField("错因", text: $draft.errorCause).textFieldStyle(NativeTextFieldStyle())
            Picker("掌握状态", selection: $draft.status) {
                Text("未掌握").tag("未掌握")
                Text("已掌握").tag("已掌握")
            }.pickerStyle(.segmented)
            NativeFieldLabel(title: "解析与笔记")
            editor(text: $draft.content, height: 120)
        }
        .nativeCard()
    }

    private var noteFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("笔记标题", text: $draft.title).textFieldStyle(NativeTextFieldStyle())
            TextField("笔记标签", text: $draft.type).textFieldStyle(NativeTextFieldStyle())
            TextField("考点（可选）", text: $draft.knowledgePoint).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "正文")
            editor(text: $draft.content, height: 240)
            Text("当前先使用原生纯文本输入；第五阶段统一替换为 TextKit 富文本编辑器。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .nativeCard()
    }

    private var stickyFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            editor(text: $draft.content, height: 170)
            TextField("标签（可选）", text: $draft.type).textFieldStyle(NativeTextFieldStyle())
            HStack(spacing: 10) {
                ForEach(HomeRecordRepository.stickyColors, id: \.self) { hex in
                    Button { draft.colorHex = hex } label: {
                        Circle().fill(Color(homeHex: hex)).frame(width: 28, height: 28)
                            .overlay(Circle().stroke(draft.colorHex == hex ? AppTheme.accent : Color.primary.opacity(0.14), lineWidth: draft.colorHex == hex ? 2.5 : 0.7))
                    }.buttonStyle(.plain)
                }
                Spacer()
                Toggle("置顶", isOn: $draft.pinned).font(AppTheme.inputFont).fixedSize()
            }
        }
        .nativeCard()
    }

    private var wordFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("词语", text: $draft.title).textFieldStyle(NativeTextFieldStyle())
            TextField("分类（可选）", text: $draft.type).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "释义与辨析")
            editor(text: $draft.content, height: 180)
        }
        .nativeCard()
    }

    private func editor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(AppTheme.inputFont)
            .frame(minHeight: height)
            .padding(8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private var canSave: Bool {
        switch kind {
        case .errors, .notes, .words: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stickies: !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private func save() {
        try? LibraryRecordRepository.save(kind: kind, draft: draft, records: records, context: modelContext)
        dismiss()
    }

    private func remove() {
        guard let recordID else { return }
        try? LibraryRecordRepository.remove(kind: kind, id: recordID, records: records, context: modelContext)
        dismiss()
    }
}
