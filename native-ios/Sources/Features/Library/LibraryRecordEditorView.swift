import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct LinkedRecordEditorTarget: Identifiable {
    let collection: String
    let recordID: String
    var id: String { "\(collection):\(recordID)" }
}

struct LibraryRecordEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [StoredRecord]

    let kind: LibraryContentKind
    let scope: LibraryScope
    let recordID: String?
    @State private var draft: LibraryRecordDraft
    @State private var showDelete = false
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var restoredDraft = false
    @State private var linkedEditorTarget: LinkedRecordEditorTarget?
    @State private var splitMessage: String?
    @State private var showSmartSplit = false
    @State private var smartSplitDraft = ""

    init(kind: LibraryContentKind, scope: LibraryScope, record: StoredRecord? = nil, preferredType: String = "") {
        self.kind = kind
        self.scope = scope
        recordID = record?.recordID
        var initialDraft = LibraryRecordDraft(kind: kind, scope: scope, record: record)
        if record == nil, let saved = LibraryDraftStore.load(kind: kind, scope: scope) {
            saved.applying(to: &initialDraft)
            _restoredDraft = State(initialValue: true)
        } else if record == nil, (kind == .notes || kind == .stickies), !preferredType.isEmpty {
            initialDraft.type = preferredType
        }
        if kind == .errors, !["错题", "不确定题"].contains(initialDraft.type) {
            initialDraft.type = "错题"
        }
        _draft = State(initialValue: initialDraft)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                contextCard
                if restoredDraft {
                    Label("已恢复上次未保存的草稿", systemImage: "clock.arrow.circlepath")
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 4)
                }
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
        .preference(key: RootBottomBarHiddenPreferenceKey.self, value: true)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save).disabled(!canSave)
            }
            if recordID != nil, kind != .errors {
                ToolbarItemGroup(placement: .bottomBar) {
                    Spacer()
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
        .onChange(of: draftSnapshot) { _, snapshot in
            guard recordID == nil else { return }
            LibraryDraftStore.save(snapshot, kind: kind, scope: scope)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase != .active, recordID == nil else { return }
            LibraryDraftStore.save(draftSnapshot, kind: kind, scope: scope)
        }
        .sheet(item: $linkedEditorTarget) { target in
            if let record = records.first(where: { $0.collection == target.collection && $0.recordID == target.recordID }) {
                NavigationStack {
                    LibraryRecordEditorView(
                        kind: target.collection == "errors" ? .errors : .notes,
                        scope: LibraryScope(subject: record.subject, module: record.module),
                        record: record
                    )
                }
            } else {
                NativeStatusCard(title: "记录不存在", detail: "该站内链接指向的记录可能已被删除", systemImage: "link.badge.plus", color: AppTheme.warning)
                    .padding(24)
            }
        }
        .overlay {
            if showSmartSplit {
                smartSplitDialog
            }
        }
    }

    private var contextCard: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(SubjectDefinition.all) { subject in
                    Button(subject.name) {
                        draft.subject = subject.name
                        draft.module = subject.modules.first ?? ""
                    }
                }
            } label: {
                compactProperty(title: "科目", value: draft.subject, image: "books.vertical")
            }
            if let subject = SubjectDefinition.all.first(where: { $0.name == draft.subject }), !subject.modules.isEmpty {
                Menu {
                    ForEach(subject.modules, id: \.self) { module in Button(module) { draft.module = module } }
                } label: {
                    compactProperty(title: "模块", value: draft.module, image: "square.stack.3d.up")
                }
            }
        }
        .padding(10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
    }

    private func compactProperty(title: String, value: String, image: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: image)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 10, weight: .regular)).foregroundStyle(.secondary)
                Text(value.isEmpty ? "未设置" : value)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 42)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private var errorFields: some View {
        Group {
            if draft.subject == "申论" { shenlunFields }
            else if draft.subject == "判断推理", draft.module == "图形推理" { graphErrorPriorityFields }
            else { regularErrorFields }
            errorRelations
        }
    }

    private var graphErrorPriorityFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            recordTypePicker
            NativeFieldLabel(title: "题目图片")
            imagePicker
            HStack {
                NativeFieldLabel(title: "题干")
                Spacer()
                Button(action: openSmartSplit) {
                    Label("智能拆分", systemImage: "sparkles")
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            editor(text: $draft.title, height: 90)
            NativeFieldLabel(title: "选项与答案")
            ForEach(draft.options.indices, id: \.self) { index in
                TextField("选项 \(index + 1)", text: $draft.options[index]).textFieldStyle(NativeTextFieldStyle())
            }
            HStack(spacing: 9) {
                answerPicker(title: "正确选项", selection: $draft.correctOption)
                answerPicker(title: "我的选项", selection: $draft.userOption)
            }
            NativeFieldLabel(title: "规律与识别思路")
            TextField("图形规律", text: $draft.graphRule).textFieldStyle(NativeTextFieldStyle())
            TextField("识别思路", text: $draft.recognition).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "分析与复盘")
            tagInput(
                title: "考点（可选）",
                text: $draft.knowledgePoint,
                suggestions: TagLibraryRepository.tags(kind: .knowledgePoint, module: draft.module, records: records),
                allowsMultiple: true
            )
            tagInput(
                title: "错因（可选）",
                text: $draft.errorCause,
                suggestions: TagLibraryRepository.tags(kind: .errorCause, module: draft.module, records: records)
            )
            tagInput(
                title: "思维误区（可选）",
                text: $draft.pitfall,
                suggestions: TagLibraryRepository.tags(kind: .thinkingTrap, module: draft.module, records: records)
            )
            TextField("题目来源", text: $draft.questionSource).textFieldStyle(NativeTextFieldStyle())
            TextField("全站正确率（%）", text: $draft.accuracy).keyboardType(.decimalPad).textFieldStyle(NativeTextFieldStyle())
            NativeFieldLabel(title: "错题笔记")
            richEditor(text: $draft.content, height: 110)
        }
        .padding(15)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var regularErrorFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            recordTypePicker

            compactFormSection("题目图片", image: "photo.on.rectangle.angled") {
                imagePicker
            }

            Divider()

            compactFormSection("题目与选项", image: "list.bullet.rectangle") {
                HStack {
                    NativeFieldLabel(title: "题干")
                    Spacer()
                    Button(action: openSmartSplit) {
                        Label("智能拆分", systemImage: "sparkles")
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                if let splitMessage {
                    Text(splitMessage).font(AppTheme.auxiliaryFont)
                        .foregroundStyle(splitMessage.hasPrefix("已") ? AppTheme.success : AppTheme.warning)
                }
                editor(text: $draft.title, height: 100)
                NativeFieldLabel(title: "选项")
                ForEach(draft.options.indices, id: \.self) { index in
                    HStack(spacing: 9) {
                        Text(String(UnicodeScalar(65 + index)!))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                            .frame(width: 25, height: 25)
                            .background(AppTheme.accent.opacity(0.09), in: Circle())
                        TextField("选项内容", text: $draft.options[index]).textFieldStyle(NativeTextFieldStyle())
                    }
                }
            }

            Divider()

            compactFormSection("答案与来源", image: "checkmark.circle") {
                HStack(spacing: 9) {
                    answerPicker(title: "正确选项", selection: $draft.correctOption)
                    answerPicker(title: "我的选项", selection: $draft.userOption)
                }
                HStack(spacing: 9) {
                    TextField("全站正确率（%）", text: $draft.accuracy)
                        .keyboardType(.decimalPad).textFieldStyle(NativeTextFieldStyle())
                    TextField("题目来源，例如：2024国考", text: $draft.questionSource)
                        .textFieldStyle(NativeTextFieldStyle())
                }
            }

            Divider()

            compactFormSection("考点与错因", image: "tag") {
                tagInput(
                    title: "考点（可选）",
                    text: $draft.knowledgePoint,
                    suggestions: TagLibraryRepository.tags(kind: .knowledgePoint, module: draft.module, records: records),
                    allowsMultiple: true
                )
                tagInput(
                    title: "错因（可选）",
                    text: $draft.errorCause,
                    suggestions: TagLibraryRepository.tags(kind: .errorCause, module: draft.module, records: records)
                )
                tagInput(
                    title: "思维误区（可选）",
                    text: $draft.pitfall,
                    suggestions: TagLibraryRepository.tags(kind: .thinkingTrap, module: draft.module, records: records)
                )
            }

            Divider()

            compactFormSection("错题笔记", image: "note.text") {
                Text("个人复盘心得、解析与方法总结").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                richEditor(text: $draft.content, height: 130)
            }

            if draft.subject == "言语理解", draft.module == "逻辑填空" {
                Divider()
                compactFormSection("词语辨析", image: "arrow.left.arrow.right") { comparisonGroups }
            }
        }
        .padding(15)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
    }

    private var recordTypePicker: some View {
        Picker("题目类型", selection: $draft.type) {
            Text("错题").tag("错题")
            Text("不确定题").tag("不确定题")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }

    private func answerPicker(title: String, selection: Binding<String>) -> some View {
        Menu {
            ForEach(["A", "B", "C", "D"], id: \.self) { value in
                Button(value) { selection.wrappedValue = value }
            }
        } label: {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(selection.wrappedValue.isEmpty ? "请选择" : selection.wrappedValue)
                        .font(AppTheme.inputFont)
                        .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : Color.primary)
                }
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 42)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func compactFormSection<Content: View>(
        _ title: String,
        image: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: image)
                .font(.system(size: 13, weight: .medium))
            content()
        }
    }

    private func tagInput(
        title: String,
        text: Binding<String>,
        suggestions: [String],
        allowsMultiple: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField(title, text: text)
                .textFieldStyle(NativeTextFieldStyle())
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(suggestions, id: \.self) { value in
                            let selected = tagSelection(text.wrappedValue, contains: value, allowsMultiple: allowsMultiple)
                            Button {
                                text.wrappedValue = updatedTagSelection(
                                    text.wrappedValue,
                                    value: value,
                                    selected: selected,
                                    allowsMultiple: allowsMultiple
                                )
                            } label: {
                                Text(value)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(selected ? AppTheme.accent : Color.secondary)
                                    .padding(.horizontal, 8)
                                    .frame(height: 26)
                                    .background(selected ? AppTheme.accent.opacity(0.09) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func tagSelection(_ rawValue: String, contains value: String, allowsMultiple: Bool) -> Bool {
        if !allowsMultiple { return rawValue.trimmingCharacters(in: .whitespacesAndNewlines) == value }
        return splitTags(rawValue).contains(value)
    }

    private func updatedTagSelection(
        _ rawValue: String,
        value: String,
        selected: Bool,
        allowsMultiple: Bool
    ) -> String {
        guard allowsMultiple else { return selected ? "" : value }
        var values = splitTags(rawValue)
        if selected { values.removeAll { $0 == value } }
        else { values.append(value) }
        return values.joined(separator: "、")
    }

    private func splitTags(_ rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var smartSplitDialog: some View {
        NativeEditorDialog(
            title: "智能拆分题目",
            canSave: !smartSplitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            actionTitle: "识别并填入",
            onClose: {
                showSmartSplit = false
                splitMessage = nil
            },
            onSave: applySmartSplit
        ) {
            Text("粘贴完整题干、A/B/C/D 选项和答案。识别成功后会分别填入表单，原内容不会在识别失败时被覆盖。")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
            TextEditor(text: $smartSplitDraft)
                .font(AppTheme.inputFont)
                .frame(minHeight: 220)
                .padding(8)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
            if let splitMessage, !splitMessage.hasPrefix("已") {
                Text(splitMessage)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.warning)
            }
        }
    }

    private func errorSection<Content: View>(
        _ title: String,
        image: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(title, systemImage: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.primary)
            content()
        }
        .nativeCard(padding: 15)
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.7)
        }
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
            DisclosureGroup("思维导图") {
                NativeMindMapEditor(encodedDocument: $draft.mindMapData).padding(.top, 8)
            }
            DisclosureGroup("涂鸦与手写") {
                NativePencilDrawingEditor(
                    encodedData: $draft.pencilKitData,
                    legacyPreviewDataURL: draft.legacyDrawingPreview
                )
                .padding(.top, 8)
            }
            multiRelationSection(title: "关联错题", candidates: relationCandidates(collection: "errors"), selection: $draft.linkedErrorIDs)
            Text("正文使用 TextKit 2 原生富文本编辑器，思维导图和 PencilKit 手写数据随当前笔记保存。")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .nativeCard()
    }

    private var stickyFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeRichTextEditor(html: $draft.content, minHeight: 170, mode: .compact)
            Menu {
                Button("无标签") { draft.type = "" }
                ForEach(stickyTags) { item in Button(item.name) { draft.type = item.name } }
            } label: {
                NativePropertyRow(title: "便签标签", value: draft.type.isEmpty ? "无标签" : draft.type, systemImage: "tag") {}
                    .allowsHitTesting(false)
            }
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
            Menu {
                ForEach(WordCategory.allCases) { category in
                    Button(category.title) {
                        draft.type = category.rawValue
                        ensureComparisonTerms()
                    }
                }
            } label: {
                NativePropertyRow(title: "词语类型", value: wordCategory.title, systemImage: wordCategory.systemImage) {}
                    .allowsHitTesting(false)
            }

            if wordCategory.isComparison {
                NativeFieldLabel(title: "辨析词语")
                ForEach($draft.wordCompareTerms) { $term in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            TextField("词语名称", text: $term.name).textFieldStyle(NativeTextFieldStyle())
                            if draft.wordCompareTerms.count > 2 {
                                Button(role: .destructive) {
                                    draft.wordCompareTerms.removeAll { $0.id == term.id }
                                    syncComparisonTitle()
                                } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain)
                            }
                        }
                        TextField("该词的独立解释", text: $term.meaning, axis: .vertical)
                            .textFieldStyle(NativeTextFieldStyle())
                            .lineLimit(2...4)
                    }
                    .padding(10)
                    .background(AppTheme.groupedBackground, in: RoundedRectangle(cornerRadius: 10))
                    .onChange(of: term.name) { _, _ in syncComparisonTitle() }
                }
                Button {
                    draft.wordCompareTerms.append(.init())
                } label: {
                    Label("增加词语", systemImage: "plus.circle")
                        .font(AppTheme.inputFont.weight(.semibold))
                }
                TextField("核心区别", text: $draft.compareNote, axis: .vertical)
                    .textFieldStyle(NativeTextFieldStyle())
                    .lineLimit(2...5)
            } else {
                TextField(wordCategory == .idiomDefinition ? "成语" : "实词", text: $draft.title)
                    .textFieldStyle(NativeTextFieldStyle())
                TextField("拼音（可选）", text: $draft.pinyin).textFieldStyle(NativeTextFieldStyle())
            }

            Menu {
                Button("未设置") { draft.sentiment = "" }
                ForEach(["褒义", "贬义", "中性"], id: \.self) { value in Button(value) { draft.sentiment = value } }
            } label: {
                NativePropertyRow(title: "感情色彩", value: draft.sentiment.isEmpty ? "未设置" : draft.sentiment, systemImage: "face.smiling") {}
                    .allowsHitTesting(false)
            }
            if wordCategory == .wordDefinition {
                TextField("词性（例如：动词）", text: $draft.partOfSpeech).textFieldStyle(NativeTextFieldStyle())
            }
            NativeFieldLabel(title: wordCategory.isComparison ? "整体释义" : "释义")
            richEditor(text: $draft.content, height: 145)
            TextField("例句（可选）", text: $draft.example, axis: .vertical)
                .textFieldStyle(NativeTextFieldStyle())
                .lineLimit(2...4)
            if wordCategory == .wordDefinition {
                TextField("我的理解", text: $draft.myUnderstanding, axis: .vertical).textFieldStyle(NativeTextFieldStyle()).lineLimit(2...4)
                TextField("常见搭配", text: $draft.collocations, axis: .vertical).textFieldStyle(NativeTextFieldStyle()).lineLimit(2...4)
                TextField("来源", text: $draft.wordSource).textFieldStyle(NativeTextFieldStyle())
            }
            multiRelationSection(title: "关联错题", candidates: relationCandidates(collection: "errors"), selection: $draft.linkedErrorIDs)
        }
        .nativeCard()
        .onAppear {
            if draft.type.isEmpty { draft.type = WordCategory.idiomDefinition.rawValue }
            ensureComparisonTerms()
        }
    }

    private var wordCategory: WordCategory {
        WordCategory(rawValue: draft.type) ?? .idiomDefinition
    }

    private func ensureComparisonTerms() {
        guard wordCategory.isComparison else { return }
        while draft.wordCompareTerms.count < 2 { draft.wordCompareTerms.append(.init()) }
        syncComparisonTitle()
    }

    private func syncComparisonTitle() {
        guard wordCategory.isComparison else { return }
        let names = draft.wordCompareTerms.map { $0.name.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !names.isEmpty { draft.title = names.joined(separator: " vs ") }
    }

    private var errorRelations: some View {
        VStack(alignment: .leading, spacing: 12) {
            NativeFieldLabel(title: "内容关联")
            Menu {
                Button("不关联套卷") { draft.sourceExamID = "" }
                ForEach(relationCandidates(collection: "exams"), id: \.recordID) { record in
                    Button(record.title) { draft.sourceExamID = record.recordID }
                }
            } label: {
                NativePropertyRow(
                    title: "来源套卷",
                    value: relationTitle(collection: "exams", id: draft.sourceExamID),
                    systemImage: "doc.text"
                ) {}
                .allowsHitTesting(false)
            }
            multiRelationSection(title: "关联笔记", candidates: relationCandidates(collection: "notes"), selection: $draft.linkedNoteIDs)
            multiRelationSection(title: "关联词语", candidates: relationCandidates(collection: "words"), selection: $draft.linkedWordIDs)
        }
        .nativeCard()
    }

    private func multiRelationSection(
        title: String,
        candidates: [StoredRecord],
        selection: Binding<[String]>
    ) -> some View {
        DisclosureGroup("\(title)（\(selection.wrappedValue.count)）") {
            if candidates.isEmpty {
                Text("暂无可关联内容").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(candidates, id: \.compoundID) { record in
                        Button {
                            var values = Set(selection.wrappedValue)
                            if values.contains(record.recordID) { values.remove(record.recordID) }
                            else { values.insert(record.recordID) }
                            selection.wrappedValue = Array(values).sorted()
                        } label: {
                            HStack {
                                Image(systemName: selection.wrappedValue.contains(record.recordID) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selection.wrappedValue.contains(record.recordID) ? AppTheme.accent : .secondary)
                                Text(record.title).font(AppTheme.inputFont).foregroundStyle(.primary).lineLimit(2)
                                Spacer()
                            }
                            .padding(.vertical, 5)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 6)
            }
        }
    }

    private func relationCandidates(collection: String) -> [StoredRecord] {
        records
            .filter { $0.collection == collection && $0.recordID != recordID }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    private func relationTitle(collection: String, id: String) -> String {
        guard !id.isEmpty else { return "未关联" }
        return records.first { $0.collection == collection && $0.recordID == id }?.title ?? "记录已不存在"
    }

    private func editor(text: Binding<String>, height: CGFloat) -> some View {
        TextEditor(text: text)
            .font(AppTheme.inputFont)
            .frame(minHeight: height)
            .padding(8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func richEditor(text: Binding<String>, height: CGFloat) -> some View {
        NativeRichTextEditor(
            html: text,
            minHeight: height,
            internalLinks: internalLinkCandidates,
            onOpenInternalLink: { link in
                linkedEditorTarget = LinkedRecordEditorTarget(collection: link.collection, recordID: link.recordID)
            }
        )
    }

    private var internalLinkCandidates: [RichTextInternalLink] {
        records
            .filter { ($0.collection == "errors" || $0.collection == "notes") && $0.recordID != recordID }
            .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
            .map { RichTextInternalLink(collection: $0.collection, recordID: $0.recordID, title: $0.title) }
    }

    private var canSave: Bool {
        switch kind {
        case .errors, .notes, .words: !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .stickies: !draft.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var draftSnapshot: LibraryDraftSnapshot { LibraryDraftSnapshot(draft) }

    private var noteTypes: [NoteTypeDefinition] {
        NoteTypeRepository.types(subject: draft.subject, module: draft.subject == "资料分析" ? "" : draft.module, records: records)
    }

    private var stickyTags: [StickyTagDefinition] {
        StickyTagRepository.tags(
            subject: draft.subject,
            module: draft.subject == "资料分析" ? "" : draft.module,
            records: records
        )
    }

    private func save() {
        if kind == .errors {
            try? TagLibraryRepository.add(
                splitTags(draft.knowledgePoint),
                kind: .knowledgePoint,
                module: draft.module,
                records: records,
                context: modelContext
            )
            try? TagLibraryRepository.add(
                [draft.errorCause],
                kind: .errorCause,
                module: draft.module,
                records: records,
                context: modelContext
            )
            try? TagLibraryRepository.add(
                [draft.pitfall],
                kind: .thinkingTrap,
                module: draft.module,
                records: records,
                context: modelContext
            )
        }
        try? LibraryRecordRepository.save(kind: kind, draft: draft, records: records, context: modelContext)
        if recordID == nil { LibraryDraftStore.clear(kind: kind, scope: scope) }
        dismiss()
    }

    private func remove() {
        guard let recordID else { return }
        try? LibraryRecordRepository.remove(kind: kind, id: recordID, records: records, context: modelContext)
        dismiss()
    }

    private func openSmartSplit() {
        smartSplitDraft = ""
        splitMessage = nil
        showSmartSplit = true
    }

    private func applySmartSplit() {
        switch ErrorQuestionParser.parse(smartSplitDraft) {
        case .success(let result):
            draft.title = result.question
            draft.options = result.options + Array(repeating: "", count: max(0, 4 - result.options.count))
            if let correct = result.correctOption { draft.correctOption = correct }
            if let selected = result.userOption { draft.userOption = selected }
            splitMessage = "已拆分题干和 \(result.options.count) 个选项，请核对后保存"
            showSmartSplit = false
        case .failure(let error):
            splitMessage = error.localizedDescription
        }
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

private struct ParsedErrorQuestion {
    let question: String
    let options: [String]
    let correctOption: String?
    let userOption: String?
}

private enum ErrorQuestionParser {
    private struct ParseFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func parse(_ rawValue: String) -> Result<ParsedErrorQuestion, Error> {
        let source = normalized(rawValue)
        guard !source.isEmpty else {
            return .failure(ParseFailure(message: "请先粘贴完整题目。"))
        }
        guard let expression = try? NSRegularExpression(
            pattern: "(?m)(?:^|\\s)([A-H])[\\.、．:：\\)）]\\s*"
        ) else {
            return .failure(ParseFailure(message: "拆分规则初始化失败。"))
        }

        let sourceNSString = source as NSString
        let answerStart = firstAnswerRange(in: source)?.location ?? sourceNSString.length
        let optionRange = NSRange(location: 0, length: answerStart)
        let matches = expression.matches(in: source, range: optionRange)
        guard matches.count >= 2, let first = matches.first else {
            return .failure(ParseFailure(message: "没有识别到连续选项，请确认选项使用 A.、B.、C.、D. 等标记。"))
        }

        let question = sourceNSString.substring(with: NSRange(location: 0, length: first.range.location))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = []
        for (index, match) in matches.enumerated() {
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : answerStart
            let value = sourceNSString.substring(with: NSRange(location: start, length: max(0, end - start)))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { options.append(value) }
        }
        guard !question.isEmpty, options.count >= 2 else {
            return .failure(ParseFailure(message: "题干或选项内容不完整，当前表单没有被修改。"))
        }

        return .success(
            ParsedErrorQuestion(
                question: question,
                options: options,
                correctOption: answerLetter(in: source, labels: ["正确答案", "参考答案", "答案"]),
                userOption: answerLetter(in: source, labels: ["我的答案", "你的答案", "用户答案"])
            )
        )
    }

    private static func normalized(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstAnswerRange(in source: String) -> NSRange? {
        let patterns = ["(?:正确答案|参考答案|我的答案|你的答案|用户答案|答案)\\s*[：:]", "(?m)^\\s*解析\\s*[：:]"]
        let fullRange = NSRange(location: 0, length: (source as NSString).length)
        var ranges: [NSRange] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: source, range: fullRange)
            else { continue }
            ranges.append(match.range)
        }
        return ranges.min { $0.location < $1.location }
    }

    private static func answerLetter(in source: String, labels: [String]) -> String? {
        let nsSource = source as NSString
        let range = NSRange(location: 0, length: nsSource.length)
        let specificLabels = labels.filter { $0 != "答案" }
        if !specificLabels.isEmpty {
            let labelPattern = specificLabels.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
            let pattern = "(?:\(labelPattern\))\\s*[：:]?\\s*([A-D])"
            if let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
               let match = expression.firstMatch(in: source, range: range), match.numberOfRanges > 1 {
                return nsSource.substring(with: match.range(at: 1)).uppercased()
            }
        }
        guard labels.contains("答案"),
              let expression = try? NSRegularExpression(pattern: "(?m)^\\s*答案\\s*[：:]?\\s*([A-D])", options: .caseInsensitive),
              let match = expression.firstMatch(in: source, range: range), match.numberOfRanges > 1
        else { return nil }
        return nsSource.substring(with: match.range(at: 1)).uppercased()
    }
}
