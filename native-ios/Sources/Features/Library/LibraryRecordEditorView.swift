import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct LibraryRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]

    let kind: LibraryContentKind
    let scope: LibraryScope
    let recordID: String?
    @State private var draft: LibraryRecordDraft
    @State private var showDelete = false
    @State private var selectedPhotos: [PhotosPickerItem] = []

    init(kind: LibraryContentKind, scope: LibraryScope, record: StoredRecord? = nil, preferredType: String = "") {
        self.kind = kind
        self.scope = scope
        recordID = record?.recordID
        var initialDraft = LibraryRecordDraft(kind: kind, scope: scope, record: record)
        if record == nil, kind == .notes, !preferredType.isEmpty { initialDraft.type = preferredType }
        _draft = State(initialValue: initialDraft)
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
        .onChange(of: selectedPhotos) { _, items in
            Task { await appendImages(items) }
        }
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
        Group {
            if draft.subject == "申论" { shenlunFields }
            else { regularErrorFields }
        }
    }

    private var regularErrorFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeFieldLabel(title: "题目")
            editor(text: $draft.title, height: 100)
            imagePicker
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
            TextField("思维误区", text: $draft.pitfall).textFieldStyle(NativeTextFieldStyle())
            TextField("题目来源", text: $draft.questionSource).textFieldStyle(NativeTextFieldStyle())
            Picker("掌握状态", selection: $draft.status) {
                Text("未掌握").tag("未掌握")
                Text("已掌握").tag("已掌握")
            }.pickerStyle(.segmented)
            NativeFieldLabel(title: "解析与笔记")
            richEditor(text: $draft.content, height: 120)
            DisclosureGroup("涂鸦与手写") {
                NativePencilDrawingEditor(encodedData: $draft.pencilKitData).padding(.top, 8)
            }
            if draft.subject == "言语理解", draft.module == "逻辑填空" { comparisonGroups }
            if draft.subject == "判断推理", draft.module == "图形推理" { graphFields }
        }
        .nativeCard()
    }

    private var imagePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NativeFieldLabel(title: "题目与选项图片")
                Spacer()
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                    Label("添加图片", systemImage: "photo.badge.plus").font(AppTheme.inputFont.weight(.semibold))
                }
            }
            if !draft.images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(draft.images.enumerated()), id: \.offset) { index, value in
                            ZStack(alignment: .topTrailing) {
                                if let image = image(from: value) {
                                    Image(uiImage: image).resizable().scaledToFill().frame(width: 90, height: 74).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 9))
                                } else {
                                    RoundedRectangle(cornerRadius: 9).fill(Color.primary.opacity(0.06)).frame(width: 90, height: 74)
                                        .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                                }
                                Button { draft.images.remove(at: index) } label: {
                                    Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                                }.buttonStyle(.plain).offset(x: 5, y: -5)
                            }
                        }
                    }.padding(.vertical, 4)
                }
            }
        }
    }

    private var comparisonGroups: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                NativeFieldLabel(title: "词语辨析组")
                Spacer()
                Button { draft.compareGroups.append(.init()) } label: { Label("新增一组", systemImage: "plus") }
                    .font(AppTheme.inputFont.weight(.semibold))
            }
            ForEach($draft.compareGroups) { $group in
                VStack(spacing: 8) {
                    HStack {
                        TextField("词语，例如：推脱 / 推托", text: $group.words).textFieldStyle(NativeTextFieldStyle())
                        Button { draft.compareGroups.removeAll { $0.id == group.id } } label: {
                            Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                        }.buttonStyle(.plain)
                    }
                    TextField("关系与区别", text: $group.relation).textFieldStyle(NativeTextFieldStyle())
                }
                .padding(10).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var graphFields: some View {
        VStack(alignment: .leading, spacing: 9) {
            NativeFieldLabel(title: "图形推理复盘")
            TextField("图形规律", text: $draft.graphRule).textFieldStyle(NativeTextFieldStyle())
            TextField("识别思路", text: $draft.recognition).textFieldStyle(NativeTextFieldStyle())
            Text("这些字段将显示在图推闪卡背面。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private var shenlunFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeFieldLabel(title: "题目信息")
            editor(text: $draft.title, height: 110)
            HStack {
                TextField("得分", text: $draft.score).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
                TextField("总分", text: $draft.totalScore).keyboardType(.numberPad).textFieldStyle(NativeTextFieldStyle())
            }
            TextField("题目来源", text: $draft.questionSource).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "框架对比")
            editor(text: $draft.myFramework, height: 110)
            editor(text: $draft.standardFramework, height: 110)
            NativeFieldLabel(title: "逐段分析差距")
            editor(text: $draft.paragraph, height: 120)
            HStack {
                NativeFieldLabel(title: "核心思维偏差")
                Spacer()
                Button { draft.bias.append(.init()) } label: { Label("添加一行", systemImage: "plus") }
                    .font(AppTheme.inputFont.weight(.semibold))
            }
            ForEach($draft.bias) { $row in
                HStack {
                    TextField("我的错误", text: $row.wrong).textFieldStyle(NativeTextFieldStyle())
                    TextField("正确思维", text: $row.right).textFieldStyle(NativeTextFieldStyle())
                    Button { draft.bias.removeAll { $0.id == row.id } } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                }
            }
            stringList(title: "我错误的踩分点", values: $draft.wrongList)
            stringList(title: "我遗漏的踩分点", values: $draft.missedList)
            NativeFieldLabel(title: "复盘笔记")
            richEditor(text: $draft.content, height: 110)
        }
        .nativeCard()
    }

    private func stringList(title: String, values: Binding<[String]>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                NativeFieldLabel(title: title)
                Spacer()
                Button { values.wrappedValue.append("") } label: { Image(systemName: "plus.circle") }
            }
            ForEach(values.wrappedValue.indices, id: \.self) { index in
                HStack {
                    TextField(title, text: values[index]).textFieldStyle(NativeTextFieldStyle())
                    Button { values.wrappedValue.remove(at: index) } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                }
            }
        }
    }

    private var noteFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("笔记标题", text: $draft.title).textFieldStyle(NativeTextFieldStyle())
            Menu {
                Button("全部（不设置标签）") { draft.type = "" }
                ForEach(noteTypes) { item in Button(item.name) { draft.type = item.name } }
            } label: {
                NativePropertyRow(title: "笔记标签", value: draft.type.isEmpty ? "全部" : draft.type, systemImage: "tag") {}
                    .allowsHitTesting(false)
            }
            TextField("考点（可选）", text: $draft.knowledgePoint).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "正文")
            richEditor(text: $draft.content, height: 240)
            Text("当前先使用原生纯文本输入；第五阶段统一替换为 TextKit 富文本编辑器。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .nativeCard()
    }

    private var stickyFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeRichTextEditor(html: $draft.content, minHeight: 170, mode: .compact)
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
            richEditor(text: $draft.content, height: 180)
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

    private func richEditor(text: Binding<String>, height: CGFloat) -> some View {
        NativeRichTextEditor(html: text, minHeight: height)
    }

    private var canSave: Bool {
        switch kind {
        case .errors, .notes, .words: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stickies: !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var noteTypes: [NoteTypeDefinition] {
        NoteTypeRepository.types(subject: draft.subject, module: draft.subject == "资料分析" ? "" : draft.module, records: records)
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

    @MainActor
    private func appendImages(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), !data.isEmpty else { continue }
            draft.images.append("data:image/jpeg;base64,\(data.base64EncodedString())")
        }
        selectedPhotos = []
    }

    private func image(from value: String) -> UIImage? {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...])).flatMap(UIImage.init(data:))
    }
}
