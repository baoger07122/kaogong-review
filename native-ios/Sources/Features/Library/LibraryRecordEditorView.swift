import PhotosUI
import SwiftData
import SwiftUI
import UIKit

private struct LinkedRecordEditorTarget: Identifiable {
    let collection: String
    let recordID: String
    var id: String { "\(collection):\(recordID)" }
}

private enum ErrorAnswerField: Hashable {
    case correct, selected
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
    @State private var activeTags: ManagedTagKind?
    @State private var activeRelation: String?
    @State private var expandedAnswerField: ErrorAnswerField?

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
        configuredEditor
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
        .overlay { editorDialogs }
    }

    private var editorContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if kind == .errors { recordTypePicker }
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
            .padding(.horizontal, kind == .errors ? 16 : 20)
            .padding(.top, kind == .errors ? 5 : 20)
            .padding(.bottom, 20)
            .frame(maxWidth: kind == .errors ? 920 : .infinity)
            .frame(maxWidth: .infinity)
        }
        .background(kind == .errors ? Color.white : AppTheme.groupedBackground)
    }

    private var configuredEditor: some View {
        editorContent
        .navigationTitle(recordID == nil ? "新增\(kind.rawValue)" : "编辑\(kind.rawValue)")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    @ViewBuilder private var editorDialogs: some View {
            if showSmartSplit {
                smartSplitDialog
            }
            if let activeTags {
                LibraryTagSelectionDialog(kind: activeTags, module: draft.module,
                    selection: activeTags == .knowledgePoint ? $draft.knowledgePoint : $draft.errorCause,
                    onClose: { self.activeTags = nil })
            }
            if let activeRelation {
                LibraryRelationSelectionDialog(collection: activeRelation,
                    candidates: relationCandidates(collection: activeRelation),
                    selection: relationBinding(activeRelation), onClose: { self.activeRelation = nil })
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
        .padding(kind == .errors ? 12 : 10)
        .background(Color.white, in: RoundedRectangle(cornerRadius: kind == .errors ? 16 : 9, style: .continuous))
        .overlay {
            if kind == .errors {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8)
            }
        }
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
        .background(Color.primary.opacity(kind == .errors ? 0 : 0.035), in: RoundedRectangle(cornerRadius: 9))
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
        VStack(alignment: .leading, spacing: 10) {
            errorFormCard {
                imagePicker
            }
            errorFormCard {
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
                    errorQuestionEditor(text: $draft.title)
                    NativeFieldLabel(title: "选项")
                    ForEach(draft.options.indices, id: \.self) { index in
                        HStack(spacing: 7) {
                            Text(String(UnicodeScalar(65 + index)!))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.primary)
                                .frame(width: 21)
                            TextField("选项内容", text: $draft.options[index])
                                .textFieldStyle(ErrorFormTextFieldStyle())
                        }
                    }
                }
            }
            errorFormCard {
                compactFormSection("答案与来源", image: "checkmark.circle") {
                    HStack(alignment: .top, spacing: 8) {
                        answerPicker(title: "正确选项", field: .correct, selection: $draft.correctOption)
                        answerPicker(title: "我的选项", field: .selected, selection: $draft.userOption)
                    }
                    HStack(spacing: 8) {
                        TextField("全站正确率（%）", text: $draft.accuracy)
                            .keyboardType(.decimalPad).textFieldStyle(ErrorFormTextFieldStyle())
                        TextField("题目来源", text: $draft.questionSource)
                            .textFieldStyle(ErrorFormTextFieldStyle())
                    }
                }
            }
            errorFormCard {
                compactFormSection("规律与识别思路", image: "eye") {
                    TextField("图形规律", text: $draft.graphRule).textFieldStyle(ErrorFormTextFieldStyle())
                    TextField("识别思路", text: $draft.recognition).textFieldStyle(ErrorFormTextFieldStyle())
                }
            }
            errorFormCard {
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
            }
            errorFormCard {
                compactFormSection("错题笔记", image: "note.text") {
                    richEditor(text: $draft.content, height: 110)
                }
            }
        }
        .background(Color.white)
    }

    private var regularErrorFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            errorFormCard {
                imagePicker
            }

            errorFormCard {
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
                errorQuestionEditor(text: $draft.title)
                NativeFieldLabel(title: "选项")
                ForEach(draft.options.indices, id: \.self) { index in
                    HStack(spacing: 7) {
                        Text(String(UnicodeScalar(65 + index)!))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                            .frame(width: 21)
                        TextField("选项内容", text: $draft.options[index])
                            .textFieldStyle(ErrorFormTextFieldStyle())
                    }
                }
            }
            }

            errorFormCard {
                compactFormSection("答案与来源", image: "checkmark.circle") {
                HStack(alignment: .top, spacing: 8) {
                    answerPicker(title: "正确选项", field: .correct, selection: $draft.correctOption)
                    answerPicker(title: "我的选项", field: .selected, selection: $draft.userOption)
                }
                HStack(spacing: 8) {
                    TextField("全站正确率（%）", text: $draft.accuracy)
                        .keyboardType(.decimalPad).textFieldStyle(ErrorFormTextFieldStyle())
                    TextField("题目来源，例如：2024国考", text: $draft.questionSource)
                        .textFieldStyle(ErrorFormTextFieldStyle())
                }
            }
            }

            errorFormCard {
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
            }

            errorFormCard {
                compactFormSection("错题笔记", image: "note.text") {
                Text("个人复盘心得、解析与方法总结").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                richEditor(text: $draft.content, height: 130)
            }
            }

            if draft.subject == "言语理解", draft.module == "逻辑填空" {
                errorFormCard {
                    compactFormSection("词语辨析", image: "arrow.left.arrow.right") { comparisonGroups }
                }
            }
        }
        .background(Color.white)
    }

    private var recordTypePicker: some View {
        Picker("题目类型", selection: $draft.type) {
            Text("错题").tag("错题")
            Text("不确定题").tag("不确定题")
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 300)
    }

    private func answerPicker(title: String, field: ErrorAnswerField, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Button {
                withoutAnimation { expandedAnswerField = expandedAnswerField == field ? nil : field }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.wrappedValue.isEmpty ? "请选择" : selection.wrappedValue)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expandedAnswerField == field {
                HStack(spacing: 5) {
                    ForEach(["A", "B", "C", "D"], id: \.self) { value in
                        Button {
                            selection.wrappedValue = value
                            withoutAnimation { expandedAnswerField = nil }
                        } label: {
                            Text(value)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selection.wrappedValue == value ? AppTheme.accent : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 27)
                                .background(selection.wrappedValue == value ? AppTheme.accent.opacity(0.09) : Color.white,
                                            in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(selection.wrappedValue == value ? AppTheme.accent.opacity(0.55) : Color.primary.opacity(0.1), lineWidth: 0.8))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }

    private func compactFormSection<Content: View>(
        _ title: String,
        image: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: image)
                .font(.system(size: 13, weight: .medium))
            content()
        }
    }

    private func errorFormCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8)
        }
    }

    private func errorQuestionEditor(text: Binding<String>) -> some View {
        TextEditor(text: text)
            .font(.system(size: 12.5, weight: .regular))
            .lineSpacing(3)
            .scrollContentBackground(.hidden)
            .frame(minHeight: 70)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
    }

    private func tagInput(
        title: String,
        text: Binding<String>,
        suggestions: [String],
        allowsMultiple: Bool = false
    ) -> some View {
        Group {
            if title.hasPrefix("思维误区") {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("思维误区").font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(width: 66, alignment: .leading)
                    TextField("可留空", text: text, axis: .vertical)
                        .font(.system(size: 12.5, weight: .regular)).lineLimit(1...5)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
            } else {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    activeTags = allowsMultiple ? .knowledgePoint : .errorCause
                } label: {
                    HStack(spacing: 8) {
                        Text(allowsMultiple ? "考点" : "错因")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                            .frame(width: 66, alignment: .leading)
                        if text.wrappedValue.isEmpty {
                            Text("选择或新增").font(.system(size: 12)).foregroundStyle(.tertiary)
                            Spacer()
                        } else {
                            NativeTagFlow {
                                ForEach(allowsMultiple ? splitTags(text.wrappedValue) : [text.wrappedValue], id: \.self) { value in
                                    Text(value).font(.system(size: 11)).foregroundStyle(AppTheme.accent)
                                        .padding(.horizontal, 7).padding(.vertical, 4)
                                        .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                                }
                            }
                        }
                        Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }

    private func splitTags(_ rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var smartSplitDialog: some View {
        ErrorSmartSplitDialog(
            text: $smartSplitDraft,
            errorMessage: splitMessage?.hasPrefix("已") == false ? splitMessage : nil,
            canApply: !smartSplitDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onCancel: {
                showSmartSplit = false
                splitMessage = nil
            },
            onApply: applySmartSplit
        )
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
        .background(Color.white)
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
        VStack(alignment: .leading, spacing: 0) {
            Text("内容关联").font(.system(size: 11)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            ForEach(["exams", "notes", "words"], id: \.self) { collection in
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    activeRelation = collection
                } label: {
                    NativeDocumentProperty(title: collection == "exams" ? "来源套卷" : (collection == "notes" ? "关联笔记" : "关联词语"),
                        value: relationSummary(collection))
                }.buttonStyle(.plain)
            }
        }
    }

    private func relationSummary(_ collection: String) -> String {
        if collection == "exams" { return relationTitle(collection: collection, id: draft.sourceExamID) }
        let count = collection == "notes" ? draft.linkedNoteIDs.count : draft.linkedWordIDs.count
        return count == 0 ? "未关联" : "已关联 \(count) 项"
    }

    private func relationBinding(_ collection: String) -> Binding<[String]> {
        switch collection {
        case "exams": return Binding(get: { draft.sourceExamID.isEmpty ? [] : [draft.sourceExamID] }, set: { draft.sourceExamID = $0.first ?? "" })
        case "notes": return $draft.linkedNoteIDs
        default: return $draft.linkedWordIDs
        }
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
            .scrollContentBackground(.hidden)
            .frame(minHeight: height)
            .padding(8)
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))
    }

    private func richEditor(text: Binding<String>, height: CGFloat) -> some View {
        NativeRichTextEditor(
            html: text,
            minHeight: height,
            documentStyle: kind == .errors,
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
            // 思维误区是普通文字，不写入标签库。
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

private struct ErrorFormTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .font(.system(size: 12.5, weight: .regular))
            .padding(.horizontal, 11)
            .frame(height: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
    }
}

private struct ErrorSmartSplitDialog: View {
    @Binding var text: String
    let errorMessage: String?
    let canApply: Bool
    let onCancel: () -> Void
    let onApply: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.24).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("智能拆分题目")
                        .font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 30, height: 30)
                            .background(Color.primary.opacity(0.06), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $text)
                    .font(.system(size: 12.5, weight: .regular))
                    .lineSpacing(3)
                    .scrollContentBackground(.hidden)
                    .frame(height: 148)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.13), lineWidth: 0.8))

                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(AppTheme.warning)
                }

                HStack(spacing: 10) {
                    Button("取消", action: onCancel)
                        .buttonStyle(NativeSecondaryButtonStyle())
                    Button("识别并填入", action: onApply)
                        .buttonStyle(NativePrimaryButtonStyle())
                        .disabled(!canApply)
                }
            }
            .padding(18)
            .frame(maxWidth: 560)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
            .shadow(color: .black.opacity(0.17), radius: 24, y: 10)
            .padding(24)
        }
        .transition(.opacity)
    }
}

private struct ParsedErrorQuestion {
    let question: String
    let options: [String]
    let correctOption: String?
    let userOption: String?
}

private enum ErrorQuestionParser {
    private struct OptionMarker {
        let code: Int
        let range: NSRange
    }

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
            pattern: "(?m)^[\\t \\u3000]*(?:[（(【\\[][\\t \\u3000]*)?([A-H])(?:(?:[\\t \\u3000]*[）)】\\]]|[\\t \\u3000]*[\\.、。:：)）])[\\t \\u3000]*|[\\t \\u3000]+|(?=[\\p{Han}])|[\\t \\u3000]*(?=\\n))",
            options: .caseInsensitive
        ) else {
            return .failure(ParseFailure(message: "拆分规则初始化失败。"))
        }

        let sourceNSString = source as NSString
        let answerStart = firstAnswerRange(in: source)?.location ?? sourceNSString.length
        let optionRange = NSRange(location: 0, length: answerStart)
        let markers = expression.matches(in: source, range: optionRange).compactMap { match -> OptionMarker? in
            guard match.numberOfRanges > 1, match.range(at: 1).location != NSNotFound else { return nil }
            let letter = sourceNSString.substring(with: match.range(at: 1)).uppercased()
            guard let scalar = letter.unicodeScalars.first else { return nil }
            return OptionMarker(code: Int(scalar.value), range: match.range)
        }
        var best: [OptionMarker] = []
        for start in markers.indices where markers[start].code == 65 {
            var chain = [markers[start]]
            var expected = 66
            for marker in markers[(start + 1)...] where marker.range.location >= chain.last!.range.location + chain.last!.range.length {
                if marker.code == expected {
                    chain.append(marker)
                    expected += 1
                }
            }
            if chain.count >= 2,
               chain.count > best.count || (chain.count == best.count && chain[0].range.location > (best.first?.range.location ?? -1)) {
                best = chain
            }
        }
        guard let first = best.first else {
            return .failure(ParseFailure(message: "没有识别到连续选项。请将 A、B、C、D 分行放在各选项开头。"))
        }

        let question = cleanedQuestion(
            sourceNSString.substring(with: NSRange(location: 0, length: first.range.location))
        )
        var options: [String] = []
        for (index, marker) in best.enumerated() {
            let start = marker.range.location + marker.range.length
            let end = index + 1 < best.count ? best[index + 1].range.location : answerStart
            let value = cleanedOption(sourceNSString.substring(with: NSRange(location: start, length: max(0, end - start))))
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
        let halfwidth = String(value.unicodeScalars.map { scalar -> Character in
            if (0xFF21...0xFF28).contains(scalar.value) || (0xFF41...0xFF48).contains(scalar.value),
               let converted = UnicodeScalar(scalar.value - 0xFEE0) {
                return Character(converted)
            }
            return Character(scalar)
        })
        return halfwidth
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\r\\n?", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "[．﹒]", with: ".", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func cleanedOption(_ value: String) -> String {
        value.components(separatedBy: .newlines)
            .map(compactLine)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Removes copy/paste wrapping while preserving one intentional break
    /// before the final question sentence.
    private static func cleanedQuestion(_ value: String) -> String {
        let lines = value
            .components(separatedBy: .newlines)
            .map(compactLine)
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }

        if let promptIndex = lines.indices.last(where: { isQuestionLead(lines[$0]) }), promptIndex > 0 {
            let body = lines[..<promptIndex].joined()
            let prompt = lines[promptIndex...].joined()
            return body.isEmpty ? prompt : "\(body)\n\(prompt)"
        }
        if lines.count > 1, let last = lines.last,
           last.hasSuffix("？") || last.hasSuffix("?") {
            let body = lines.dropLast().joined()
            return body.isEmpty ? last : "\(body)\n\(last)"
        }

        let merged = lines.joined()
        let nsMerged = merged as NSString
        let pattern = "(?<=[。；;])(?:以下|下列|根据上述|由此|据此|请问|上述)"
        if let expression = try? NSRegularExpression(pattern: pattern),
           let match = expression.firstMatch(
               in: merged,
               range: NSRange(location: 0, length: nsMerged.length)
           ), match.range.location > 0 {
            let body = nsMerged.substring(to: match.range.location)
            let prompt = nsMerged.substring(from: match.range.location)
            return "\(body)\n\(prompt)"
        }
        return merged
    }

    private static func compactLine(_ value: String) -> String {
        var result = value
            .replacingOccurrences(of: "[\\t\\u00A0 ]+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let cjkAndPunctuation = "\\p{Han}，。！？；：、‘’“”（）《》"
        result = result.replacingOccurrences(
            of: "([\(cjkAndPunctuation)])\\s+",
            with: "$1",
            options: .regularExpression
        )
        result = result.replacingOccurrences(
            of: "\\s+([\(cjkAndPunctuation)])",
            with: "$1",
            options: .regularExpression
        )
        return result
    }

    private static func isQuestionLead(_ value: String) -> Bool {
        ["以下", "下列", "根据上述", "由此", "据此", "请问", "上述"]
            .contains { value.hasPrefix($0) }
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
            let pattern = "(?:\(labelPattern))\\s*[：:]?\\s*([A-D])"
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
