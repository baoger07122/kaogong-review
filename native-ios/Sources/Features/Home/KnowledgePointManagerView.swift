import SwiftData
import SwiftUI
import UIKit

private struct TagEditorState: Identifiable {
    let id = UUID()
    let original: String?
}

private struct KnowledgePointTypeMove: Identifiable {
    let id = UUID()
    let name: String
    let module: String
    let sourceTypeID: String?
    let typeID: String
    let preview: VerbalKnowledgePointMigrationPreview
}

private struct KnowledgePointGroupMoveRequest: Identifiable {
    let id = UUID()
    let tagName: String
    let subject: String
    let module: String
    let typeID: String?
    let currentGroupID: String?
    let groups: [LibraryKnowledgePointGroup]
    let anchorRect: CGRect
}

private struct TagFolderAnchorPreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
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
    @State private var statusMessage: String?
    @State private var showsOrder = false
    @State private var verbalTypeSelection = Self.legacyVerbalType
    @State private var selectedGroupID: String?
    @State private var isAddingGroup = false
    @State private var editingGroupID: String?
    @State private var groupNameDraft = ""
    @State private var deletingGroup: LibraryKnowledgePointGroup?
    @State private var typeMove: KnowledgePointTypeMove?
    @State private var migrationResolutions: [String: LibraryKnowledgePointReference] = [:]
    @State private var showsMigrationReview = false
    @State private var typeMoveInformation: String?
    @State private var folderAnchors: [String: CGRect] = [:]
    @State private var groupMoveRequest: KnowledgePointGroupMoveRequest?

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
                if let statusMessage {
                    Text(statusMessage)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(AppTheme.success)
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
                                Text(name)
                                    .font(AppTheme.bodyFont)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer()
                                if kind == .knowledgePoint, !groups.isEmpty {
                                    Button { beginGroupMove(name) } label: {
                                        Image(systemName: "folder")
                                            .frame(width: 44, height: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("移动考点分组：\(name)")
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: TagFolderAnchorPreferenceKey.self,
                                                value: [name: proxy.frame(in: .named("knowledge-point-manager"))]
                                            )
                                        }
                                    }
                                }
                                if isVerbalKnowledgePoint {
                                    Menu {
                                        let targets = verbalTypes.filter { $0.id != selectedVerbalTypeID }
                                        if targets.isEmpty {
                                            Button(selectedVerbalTypeID == nil ? "请先为本模块新建题型" : "当前没有其他题型") {
                                                typeMoveInformation = selectedVerbalTypeID == nil
                                                    ? "请先为本模块新建题型，再将旧考点归入题型。"
                                                    : "当前模块没有其他可移动到的题型。"
                                            }
                                        } else {
                                            ForEach(targets) { type in
                                                Button(type.name) { beginTypeMove(name, to: type.id) }
                                            }
                                        }
                                    } label: {
                                        Text("改题型")
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(AppTheme.accent)
                                            .frame(minWidth: 44, minHeight: 44)
                                            .contentShape(Rectangle())
                                    }
                                    .accessibilityLabel("更改题型：\(name)")
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
                            if index < visibleTags.count - 1 { Divider() }
                        }
                    }
                    .padding(.horizontal, 14)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                }
            }
            .padding(20)
        }
        .coordinateSpace(name: "knowledge-point-manager")
        .onPreferenceChange(TagFolderAnchorPreferenceKey.self) { folderAnchors = $0 }
        .background {
            GeometryReader { proxy in
                KnowledgePointGroupPopoverPresenter(
                    request: $groupMoveRequest,
                    availableWidth: proxy.size.width,
                    onSelect: finishGroupMove
                )
            }
            .allowsHitTesting(false)
        }
        .background(Color.white)
        .navigationTitle("错题标签管理")
        .navigationBarTitleDisplayMode(.inline)
        .alert(Text(typeMoveInformation == nil ? "操作失败" : "改题型"), isPresented: Binding(
            get: { errorMessage != nil || typeMoveInformation != nil },
            set: { if !$0 { errorMessage = nil; typeMoveInformation = nil } }
        )) {
            Button("好", role: .cancel) { errorMessage = nil; typeMoveInformation = nil }
        } message: {
            Text(errorMessage ?? typeMoveInformation ?? "")
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
            if showsMigrationReview, let typeMove {
                VerbalKnowledgePointMigrationReviewDialog(
                    preview: typeMove.preview,
                    resolutions: $migrationResolutions,
                    onCancel: cancelTypeMove,
                    onMove: { performTypeMove(typeMove) }
                )
            } else if let typeMove {
                NativeConfirmationDialog(
                    title: "更改所属题型",
                    message: typeMoveConfirmationMessage(typeMove),
                    confirmTitle: typeMove.preview.reviewItems.isEmpty ? "移动" : "核对关联",
                    cancelTitle: "取消",
                    confirmIdentifier: "confirm-move-verbal-knowledge-point",
                    cancelIdentifier: "cancel-move-verbal-knowledge-point",
                    onConfirm: {
                        if typeMove.preview.reviewItems.isEmpty {
                            performTypeMove(typeMove)
                        } else {
                            migrationResolutions = [:]
                            showsMigrationReview = true
                        }
                    },
                    onCancel: cancelTypeMove
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
        .onChange(of: subject.name) { _, _ in moveTypeChangedScope(); selectDefaultGroupIfNeeded() }
        .onChange(of: module) { _, _ in moveTypeChangedScope(); selectDefaultGroupIfNeeded() }
        .onChange(of: selectedVerbalTypeID) { _, _ in moveTypeChangedScope(); selectDefaultGroupIfNeeded() }
        .onChange(of: kind) { _, _ in moveTypeChangedScope(); selectDefaultGroupIfNeeded() }
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
            Text("保存范围：\(subject.name) → \(module)\(selectedTypeID.map { _ in " → \(selectedVerbalTypeName)" } ?? "")")
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

    private func beginGroupMove(_ name: String) {
        guard kind == .knowledgePoint, !groups.isEmpty else { return }
        guard let anchorRect = folderAnchors[name], anchorRect.width > 0, anchorRect.height > 0 else {
            errorMessage = "无法定位分组按钮，请稍后重试。"
            return
        }
        let currentGroupID = LibraryKnowledgePointGroupRepository.groupID(
            for: name, subject: subject.name, module: module, typeID: selectedTypeID, records: records
        )
        groupMoveRequest = KnowledgePointGroupMoveRequest(
            tagName: name,
            subject: subject.name,
            module: module,
            typeID: selectedTypeID,
            currentGroupID: currentGroupID,
            groups: groups,
            anchorRect: anchorRect
        )
    }

    private func finishGroupMove(_ request: KnowledgePointGroupMoveRequest, to groupID: String?) {
        groupMoveRequest = nil
        guard request.currentGroupID != groupID else { return }
        let currentNames: [String]
        if request.subject == "言语理解", let typeID = request.typeID {
            currentNames = VerbalReasoningKnowledgePointRepository.tags(
                module: request.module, typeID: typeID, records: records
            )
        } else {
            currentNames = TagLibraryRepository.tags(
                kind: .knowledgePoint, module: request.module, records: records
            )
        }
        guard currentNames.contains(request.tagName) else {
            errorMessage = "考点目录已变化，分组未修改。请重新打开后再试。"
            return
        }
        let currentGroups = LibraryKnowledgePointGroupRepository.groups(
            subject: request.subject, module: request.module, typeID: request.typeID, records: records
        )
        guard groupID == nil || currentGroups.contains(where: { $0.id == groupID }) else {
            errorMessage = "目标分组已变化，考点未移动。请重新打开后再试。"
            return
        }
        do {
            try LibraryKnowledgePointGroupRepository.assign(
                request.tagName, to: groupID, subject: request.subject, module: request.module,
                typeID: request.typeID, records: records, context: modelContext
            )
            errorMessage = nil
        } catch {
            errorMessage = "移动考点失败：\(error.localizedDescription)"
        }
    }

    private func beginTypeMove(_ name: String, to typeID: String) {
        guard isVerbalKnowledgePoint else { return }
        let sourceTypeID = selectedVerbalTypeID
        do {
            let preview = try VerbalReasoningKnowledgePointRepository.migrationPreview(
                name, module: module, fromTypeID: sourceTypeID, toTypeID: typeID, records: records
            )
            typeMove = KnowledgePointTypeMove(
                name: name,
                module: module,
                sourceTypeID: sourceTypeID,
                typeID: typeID,
                preview: preview
            )
            migrationResolutions = [:]
            showsMigrationReview = false
            errorMessage = nil
            statusMessage = nil
        } catch {
            errorMessage = "无法准备题型迁移：\(error.localizedDescription)"
        }
    }

    private func typeMoveConfirmationMessage(_ move: KnowledgePointTypeMove) -> String {
        var message = "将考点“\(move.name)”从“\(move.preview.sourceTitle)”移动到“\(move.preview.destinationTitle)”。"
        if move.preview.destinationAlreadyExists {
            message += "目标已有同名考点，将复用现有目录项。"
        } else {
            message += "目标目录将新增此考点。"
        }
        if !move.preview.reviewItems.isEmpty {
            message += "另有 \(move.preview.reviewItems.count) 道题只保存了同名文字，下一步逐题核对关联。"
        } else {
            message += "题目本身的模块和题型、其他考点、笔记及作答保持原样。"
        }
        return message
    }

    private func performTypeMove(_ move: KnowledgePointTypeMove) {
        do {
            let result = try VerbalReasoningKnowledgePointRepository.moveKnowledgePoint(
                move.name,
                module: move.module,
                fromTypeID: move.sourceTypeID,
                toTypeID: move.typeID,
                resolving: migrationResolutions,
                records: records,
                context: modelContext
            )
            statusMessage = "已移动至\(move.preview.destinationTitle)，保留 \(result.retainedAssociationCount) 道题的关联。"
            typeMove = nil
            showsMigrationReview = false
            migrationResolutions = [:]
            errorMessage = nil
            selectDefaultGroupIfNeeded()
        } catch {
            errorMessage = "移动失败：\(error.localizedDescription)"
        }
    }

    private func cancelTypeMove() {
        typeMove = nil
        showsMigrationReview = false
        migrationResolutions = [:]
    }

    private func moveTypeChangedScope() {
        groupMoveRequest = nil
        typeMove = nil
        showsMigrationReview = false
        migrationResolutions = [:]
    }
}

private struct VerbalKnowledgePointMigrationReviewDialog: View {
    let preview: VerbalKnowledgePointMigrationPreview
    @Binding var resolutions: [String: LibraryKnowledgePointReference]
    let onCancel: () -> Void
    let onMove: () -> Void

    private var allQuestionsResolved: Bool {
        preview.reviewItems.allSatisfy { resolutions[$0.recordID] != nil }
    }

    var body: some View {
        GeometryReader { proxy in
            let dialogWidth = min(560, max(0, proxy.size.width - 32))
            let dialogHeight = min(620, max(280, proxy.size.height - 48))
            ZStack {
                Color.black.opacity(0.30).ignoresSafeArea()
                VStack(alignment: .leading, spacing: 0) {
                    Text("核对关联")
                        .font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.top, 18)
                    Text("以下题目只保存了考点名称。请选择每道题的归属，提交前不会修改数据。")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 18)
                        .padding(.top, 8)
                        .padding(.bottom, 12)

                    Divider()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(preview.reviewItems) { item in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.title.isEmpty ? item.recordID : item.title)
                                        .font(.system(size: 13, weight: .semibold))
                                        .lineLimit(2)
                                    Text(item.summary)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(3)
                                    Menu {
                                        ForEach(preview.resolutionChoices) { choice in
                                            Button(preview.resolutionChoiceTitles[choice.id] ?? choice.name) {
                                                resolutions[item.recordID] = choice
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(resolutions[item.recordID].flatMap {
                                                preview.resolutionChoiceTitles[$0.id]
                                            } ?? "选择此题的考点归属")
                                                .lineLimit(2)
                                                .multilineTextAlignment(.leading)
                                            Spacer(minLength: 4)
                                            Image(systemName: "chevron.down")
                                                .font(.system(size: 10, weight: .semibold))
                                        }
                                        .font(.system(size: 12, weight: .medium))
                                        .foregroundStyle(resolutions[item.recordID] == nil ? AppTheme.danger : AppTheme.accent)
                                        .padding(.horizontal, 10)
                                        .frame(minHeight: 40)
                                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(11)
                                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                        .padding(14)
                    }
                    .frame(maxHeight: max(120, dialogHeight - 188))

                    Divider()
                    HStack(spacing: 0) {
                        Button("取消", action: onCancel)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 48)
                        Divider().frame(height: 48)
                        Button("移动", action: onMove)
                            .fontWeight(.semibold)
                            .foregroundStyle(AppTheme.accent)
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .disabled(!allQuestionsResolved)
                    }
                    .buttonStyle(.plain)
                }
                .frame(width: dialogWidth, height: dialogHeight)
                .background(Color(uiColor: .systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 24, y: 12)
                .padding(.horizontal, 16)
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape, onCancel)
        }
    }
}

private struct KnowledgePointGroupPopoverContent: View {
    let request: KnowledgePointGroupMoveRequest
    let width: CGFloat
    let onSelect: (String?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("移动到分组")
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            ScrollView(.vertical, showsIndicators: request.groups.count > 5) {
                VStack(spacing: 0) {
                    ForEach(request.groups) { group in
                        choiceRow(group.name, isSelected: request.currentGroupID == group.id) {
                            onSelect(group.id)
                        }
                    }
                    choiceRow("未分组", isSelected: request.currentGroupID == nil) {
                        onSelect(nil)
                    }
                }
            }
            .frame(maxHeight: 264)
        }
        .padding(.vertical, 4)
        .frame(width: width, alignment: .leading)
        .background(Color(uiColor: .systemBackground))
    }

    private func choiceRow(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct KnowledgePointGroupPopoverPresenter: UIViewControllerRepresentable {
    @Binding var request: KnowledgePointGroupMoveRequest?
    let availableWidth: CGFloat
    let onSelect: (KnowledgePointGroupMoveRequest, String?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        controller.view.isUserInteractionEnabled = false
        controller.view.accessibilityElementsHidden = true
        context.coordinator.presenter = controller
        return controller
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.parent = self
        context.coordinator.presenter = controller
        guard let request else {
            context.coordinator.dismissIfNeeded()
            return
        }
        context.coordinator.present(request)
    }

    final class Coordinator: NSObject, UIPopoverPresentationControllerDelegate {
        var parent: KnowledgePointGroupPopoverPresenter
        weak var presenter: UIViewController?
        private var presentedRequestID: UUID?

        init(_ parent: KnowledgePointGroupPopoverPresenter) {
            self.parent = parent
        }

        func present(_ request: KnowledgePointGroupMoveRequest) {
            guard presentedRequestID != request.id else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self,
                      self.parent.request?.id == request.id,
                      let presenter = self.presenter,
                      presenter.view.window != nil,
                      presenter.presentedViewController == nil else { return }
                let width = max(1, min(240, self.parent.availableWidth - 32))
                let visibleRows = min(request.groups.count + 1, 6)
                let height = CGFloat(48 + visibleRows * 44)
                let content = KnowledgePointGroupPopoverContent(
                    request: request,
                    width: width,
                    onSelect: { [weak self] groupID in self?.dismissAndSelect(request, groupID: groupID) }
                )
                let hosting = UIHostingController(rootView: content)
                hosting.view.backgroundColor = .systemBackground
                hosting.preferredContentSize = CGSize(width: width, height: height)
                hosting.modalPresentationStyle = .popover
                guard let popover = hosting.popoverPresentationController else { return }
                popover.sourceView = presenter.view
                popover.sourceRect = request.anchorRect
                popover.permittedArrowDirections = [.up, .down, .left, .right]
                popover.delegate = self
                self.presentedRequestID = request.id
                presenter.present(hosting, animated: true)
            }
        }

        func dismissIfNeeded() {
            guard let active = presenter?.presentedViewController else {
                presentedRequestID = nil
                return
            }
            active.dismiss(animated: true) { [weak self] in self?.presentedRequestID = nil }
        }

        private func dismissAndSelect(_ request: KnowledgePointGroupMoveRequest, groupID: String?) {
            guard let active = presenter?.presentedViewController else { return }
            active.dismiss(animated: true) { [weak self] in
                guard let self else { return }
                self.presentedRequestID = nil
                self.parent.request = nil
                self.parent.onSelect(request, groupID)
            }
        }

        func adaptivePresentationStyle(for controller: UIPresentationController) -> UIModalPresentationStyle {
            .none
        }

        func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
            presentedRequestID = nil
            parent.request = nil
        }
    }
}
