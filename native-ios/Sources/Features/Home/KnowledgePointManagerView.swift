import SwiftData
import SwiftUI

private struct TagEditorState: Identifiable {
    let id = UUID()
    let original: String?
}

private struct LegacyKnowledgePointMove: Identifiable {
    let id = UUID()
    let name: String
    let typeID: String
    let typeName: String
}

struct KnowledgePointManagerView: View {
    private static let legacyVerbalType = "__legacy_verbal_knowledge_points__"
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
    @State private var verbalTypeSelection = Self.legacyVerbalType
    @State private var selectedGroupID: String?
    @State private var isAddingGroup = false
    @State private var editingGroupID: String?
    @State private var groupNameDraft = ""
    @State private var deletingGroup: LibraryKnowledgePointGroup?
    @State private var legacyMove: LegacyKnowledgePointMove?

    private var selectedTypeID: String? { isVerbalKnowledgePoint ? selectedVerbalTypeID : nil }
    private var groups: [LibraryKnowledgePointGroup] {
        guard kind == .knowledgePoint else { return [] }
        return LibraryKnowledgePointGroupRepository.groups(subject: subject.name, module: module, typeID: selectedTypeID, records: records)
    }
    private var visibleTags: [String] {
        guard kind == .knowledgePoint, !groups.isEmpty else { return tags }
        return LibraryKnowledgePointGroupRepository.names(
            in: selectedGroupID, allNames: tags, subject: subject.name, module: module, typeID: selectedTypeID, records: records
        )
    }

    private var isVerbalKnowledgePoint: Bool { subject.name == "言语理解" && kind == .knowledgePoint }
    private var verbalTypes: [LibraryErrorType] {
        LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
            .filter { $0.module == module }
    }
    private var selectedVerbalTypeID: String? {
        verbalTypeSelection == Self.legacyVerbalType ? nil : verbalTypeSelection
    }
    private var selectedVerbalTypeName: String {
        if verbalTypeSelection == Self.legacyVerbalType { return "旧考点" }
        return verbalTypes.first(where: { $0.id == verbalTypeSelection })?.name ?? "旧考点"
    }
    private var scopeTitle: String {
        isVerbalKnowledgePoint ? "\(module) · \(selectedVerbalTypeName)" : "\(module) · \(kind.rawValue)"
    }
    private var tags: [String] {
        guard isVerbalKnowledgePoint else {
            return TagLibraryRepository.tags(kind: kind, module: module, records: records)
        }
        guard let selectedVerbalTypeID else {
            return TagLibraryRepository.tags(kind: .knowledgePoint, module: module, records: records)
        }
        return VerbalReasoningKnowledgePointRepository.tags(
            module: module,
            typeID: selectedVerbalTypeID,
            records: records
        )
    }
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

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        subjectSelector
                        moduleSelector
                        if isVerbalKnowledgePoint { verbalTypeSelector }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        subjectSelector
                        moduleSelector
                        if isVerbalKnowledgePoint { verbalTypeSelector }
                    }
                }

                Picker("标签类型", selection: $kind) {
                    ForEach(ManagedTagKind.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                HStack {
                    Text(scopeTitle)
                        .font(AppTheme.sectionTitleFont)
                    Spacer()
                    if kind == .knowledgePoint {
                        Button("调整顺序") { showsOrder = true }
                            .font(AppTheme.inputFont.weight(.semibold))
                        Button("新增分组") {
                            isAddingGroup = true
                            editingGroupID = nil
                            groupNameDraft = ""
                        }
                        .font(AppTheme.inputFont.weight(.semibold))
                    }
                    Button { beginAdd() } label: { Label("新增", systemImage: "plus") }
                        .font(AppTheme.inputFont.weight(.semibold))
                }

                if kind == .knowledgePoint, !groups.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(groups) { group in
                                Button { selectedGroupID = group.id } label: {
                                    Text(group.name)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundStyle(selectedGroupID == group.id ? AppTheme.accent : Color.primary)
                                        .padding(.horizontal, 10).frame(height: 28)
                                        .background(selectedGroupID == group.id ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("重命名") {
                                        editingGroupID = group.id
                                        groupNameDraft = group.name
                                        isAddingGroup = true
                                    }
                                    Button("删除分组", role: .destructive) { deletingGroup = group }
                                }
                            }
                            Button("未分组") { selectedGroupID = nil }
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(selectedGroupID == nil ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10).frame(height: 28)
                                .background(selectedGroupID == nil ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                        }
                    }
                }

                if visibleTags.isEmpty {
                    NativeStatusCard(
                        title: "暂无考点",
                        detail: groups.isEmpty ? "点击新增建立当前范围的第一项" : "此分组还没有考点",
                        systemImage: "tag",
                        color: AppTheme.accent
                    )
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(visibleTags.enumerated()), id: \.element) { index, name in
                            HStack(spacing: 10) {
                                if kind != .knowledgePoint {
                                    Image(systemName: "line.3.horizontal").foregroundStyle(.tertiary)
                                }
                                Text(name).font(AppTheme.bodyFont)
                                Spacer()
                                if kind == .knowledgePoint {
                                    Menu {
                                        Button("未分组") { moveTag(name, to: nil) }
                                        ForEach(groups) { group in
                                            Button(group.name) { moveTag(name, to: group.id) }
                                        }
                                    } label: {
                                        Image(systemName: "folder")
                                    }
                                    .disabled(groups.isEmpty)
                                }
                                if kind != .knowledgePoint {
                                    Button { move(name, -1) } label: { Image(systemName: "chevron.up") }.disabled(index == 0)
                                    Button { move(name, 1) } label: { Image(systemName: "chevron.down") }.disabled(index == tags.count - 1)
                                }
                                Button { beginEdit(name) } label: { Image(systemName: "pencil") }
                                Button { deletingName = name } label: { Image(systemName: "trash").foregroundStyle(AppTheme.danger) }
                            }
                            .font(.system(size: 12, weight: .medium))
                            .frame(minHeight: 44)
                            .contextMenu {
                                if isVerbalKnowledgePoint, selectedVerbalTypeID == nil, !verbalTypes.isEmpty {
                                    Menu("归入题型") {
                                        ForEach(verbalTypes) { type in
                                            Button(type.name) {
                                                legacyMove = LegacyKnowledgePointMove(name: name, typeID: type.id, typeName: type.name)
                                            }
                                        }
                                    }
                                }
                            }
                            if index < visibleTags.count - 1 { Divider() }
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
            if isAddingGroup { groupEditorDialog }
            if let deletingGroup {
                NativeDeleteDialog(
                    title: "删除分组",
                    message: "删除“\(deletingGroup.name)”后，分组中的考点会保留并变为未分组。",
                    onDelete: { removeGroup(deletingGroup) },
                    onCancel: { self.deletingGroup = nil }
                )
            }
            if let legacyMove {
                NativeConfirmationDialog(
                    title: "归入题型",
                    message: "将旧考点“\(legacyMove.name)”归入“\(legacyMove.typeName)”？已有歧义记录会保留旧归属。",
                    confirmTitle: "归入",
                    cancelTitle: "取消",
                    confirmIdentifier: "confirm-move-legacy-knowledge-point",
                    cancelIdentifier: "cancel-move-legacy-knowledge-point",
                    onConfirm: { migrateLegacyKnowledgePoint(legacyMove) },
                    onCancel: { self.legacyMove = nil }
                )
            }
            if let deletingName {
                NativeDeleteDialog(
                    title: "删除\(kind.rawValue)",
                    message: "确定删除“\(deletingName)”？相关错题和笔记中的引用也会一并移除。",
                    onDelete: { remove(deletingName) },
                    onCancel: { self.deletingName = nil }
                )
            }
        }
        .sheet(isPresented: $showsOrder) {
            KnowledgePointOrderView(subject: subject.name, module: module, typeID: isVerbalKnowledgePoint ? selectedVerbalTypeID : nil, groupID: selectedGroupID)
        }
        .onAppear {
            resetVerbalTypeSelection()
            selectDefaultGroupIfNeeded()
        }
        .onChange(of: subject.name) { _, _ in selectDefaultGroupIfNeeded() }
        .onChange(of: module) { _, _ in selectDefaultGroupIfNeeded() }
        .onChange(of: selectedVerbalTypeID) { _, _ in selectDefaultGroupIfNeeded() }
        .onChange(of: kind) { _, _ in selectDefaultGroupIfNeeded() }
        .onChange(of: verbalTypes.map(\.id)) { _, _ in
            if isVerbalKnowledgePoint,
               !verbalTypes.contains(where: { $0.id == verbalTypeSelection }),
               verbalTypeSelection != Self.legacyVerbalType {
                resetVerbalTypeSelection()
            }
        }
    }

    private var subjectSelector: some View {
        Menu {
            ForEach(SubjectDefinition.all) { value in
                Button(value.name) {
                    subject = value
                    module = value.name == "数量关系"
                        ? (QuantityQuestionTypeRepository.types(records: records).first ?? "")
                        : (value.modules.first ?? "")
                    resetVerbalTypeSelection()
                }
            }
        } label: { selector(title: "科目", value: subject.name) }
    }

    private var moduleSelector: some View {
        Menu {
            ForEach(availableModules, id: \.self) { value in
                Button(value) {
                    module = value
                    resetVerbalTypeSelection()
                }
            }
        } label: {
            selector(title: subject.name == "数量关系" ? "题型" : "模块", value: module)
        }
    }

    private var verbalTypeSelector: some View {
        Menu {
            ForEach(verbalTypes) { type in
                Button(type.name) { verbalTypeSelection = type.id }
            }
            if !verbalTypes.isEmpty { Divider() }
            Button("旧考点") { verbalTypeSelection = Self.legacyVerbalType }
        } label: {
            selector(title: "题型", value: selectedVerbalTypeName)
        }
        .accessibilityIdentifier("verbal-knowledge-point-type-selector")
    }

    private func resetVerbalTypeSelection() {
        verbalTypeSelection = LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
            .first(where: { $0.module == module })?.id ?? Self.legacyVerbalType
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
            Text("保存范围：\(subject.name) → \(module)\(isVerbalKnowledgePoint ? " → \(selectedVerbalTypeName)" : "")")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private var groupEditorDialog: some View {
        NativeEditorDialog(
            title: editingGroupID == nil ? "新增分组" : "重命名分组",
            canSave: LibraryKnowledgePointGroupPolicy.canUseGroupName(
                groupNameDraft, groups: groups, excluding: editingGroupID
            ),
            onClose: { isAddingGroup = false },
            onSave: saveGroup
        ) {
            TextField("分组名称", text: $groupNameDraft).textFieldStyle(NativeTextFieldStyle())
            Text("保存范围：\(subject.name) → \(module)\(selectedTypeID.map { " → \(selectedVerbalTypeName)" } ?? "")")
                .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            if !LibraryKnowledgePointGroupPolicy.canUseGroupName(
                groupNameDraft, groups: groups, excluding: editingGroupID
            ) {
                Text(LibraryKnowledgePointGroupPolicy.normalizedName(groupNameDraft).isEmpty
                     ? "分组名称不能为空"
                     : "当前范围已有同名分组")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(AppTheme.danger)
            }
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
            if isVerbalKnowledgePoint, let typeID = selectedVerbalTypeID {
                if let original = editor.original {
                    try VerbalReasoningKnowledgePointRepository.rename(
                        original, to: draftName, module: module, typeID: typeID, records: records, context: modelContext
                    )
                } else {
                    try VerbalReasoningKnowledgePointRepository.add(
                        draftName, module: module, typeID: typeID, records: records, context: modelContext,
                        groupID: activeGroupForNewTag
                    )
                }
            } else {
                if let original = editor.original {
                    try TagLibraryRepository.rename(original, to: draftName, kind: kind, module: module, subject: subject.name, typeID: selectedTypeID, records: records, context: modelContext)
                } else {
                    try TagLibraryRepository.add(
                        draftName, kind: kind, module: module, records: records, context: modelContext,
                        knowledgePointGroupID: kind == .knowledgePoint ? activeGroupForNewTag : nil,
                        subject: subject.name
                    )
                }
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
            if isVerbalKnowledgePoint, let typeID = selectedVerbalTypeID {
                try VerbalReasoningKnowledgePointRepository.delete(
                    name, module: module, typeID: typeID, records: records, context: modelContext
                )
            } else {
                try TagLibraryRepository.delete(name, kind: kind, module: module, subject: subject.name, typeID: selectedTypeID, records: records, context: modelContext)
            }
            errorMessage = nil
            deletingName = nil
        } catch {
            errorMessage = "删除标签失败：\(error.localizedDescription)"
        }
    }

    private var activeGroupForNewTag: String? {
        groups.isEmpty ? nil : selectedGroupID
    }

    private func selectDefaultGroupIfNeeded() {
        selectedGroupID = LibraryKnowledgePointGroupRepository.groups(
            subject: subject.name, module: module, typeID: selectedTypeID, records: records
        ).first?.id
    }

    private func saveGroup() {
        do {
            if let editingGroupID {
                guard try LibraryKnowledgePointGroupRepository.renameGroup(
                    editingGroupID, to: groupNameDraft, subject: subject.name, module: module, typeID: selectedTypeID,
                    records: records, context: modelContext
                ) else {
                    errorMessage = "分组名称不能为空或重复"
                    return
                }
            } else {
                guard let group = try LibraryKnowledgePointGroupRepository.addGroup(
                    groupNameDraft, subject: subject.name, module: module, typeID: selectedTypeID,
                    records: records, context: modelContext
                ) else {
                    errorMessage = "分组名称不能为空或重复"
                    return
                }
                selectedGroupID = group.id
            }
            isAddingGroup = false
            errorMessage = nil
        } catch {
            errorMessage = "分组保存失败：\(error.localizedDescription)"
        }
    }

    private func removeGroup(_ group: LibraryKnowledgePointGroup) {
        do {
            try LibraryKnowledgePointGroupRepository.deleteGroup(
                group.id, subject: subject.name, module: module, typeID: selectedTypeID, records: records, context: modelContext
            )
            deletingGroup = nil
            selectDefaultGroupIfNeeded()
        } catch {
            errorMessage = "删除分组失败：\(error.localizedDescription)"
        }
    }

    private func moveTag(_ name: String, to groupID: String?) {
        do {
            try LibraryKnowledgePointGroupRepository.assign(
                name, to: groupID, subject: subject.name, module: module, typeID: selectedTypeID,
                records: records, context: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "移动考点失败：\(error.localizedDescription)"
        }
    }

    private func migrateLegacyKnowledgePoint(_ move: LegacyKnowledgePointMove) {
        do {
            try VerbalReasoningKnowledgePointRepository.migrateLegacy(
                move.name, module: module, toTypeID: move.typeID, records: records, context: modelContext
            )
            legacyMove = nil
            errorMessage = nil
            selectDefaultGroupIfNeeded()
        } catch {
            errorMessage = "归入失败，请重试：\(error.localizedDescription)"
            legacyMove = nil
        }
    }
}
