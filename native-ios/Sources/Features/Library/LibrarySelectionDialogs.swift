import SwiftData
import SwiftUI

private struct LibraryKnowledgePointOrderTarget: Identifiable {
    let subject: String
    let module: String
    let typeID: String?
    let groupID: String?
    var id: String { "\(subject)|\(module)|\(typeID ?? "legacy")|\(groupID ?? "ungrouped")" }
}

private struct LibraryKnowledgePointAddTarget: Identifiable {
    let id = UUID()
    let name: String
    let subject: String
    let module: String
    let typeID: String?
}

private struct LibraryKnowledgePointAddDestinationPopover: View {
    let target: LibraryKnowledgePointAddTarget
    let groups: [LibraryKnowledgePointGroup]
    let onCreate: (String?) -> String?
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedGroupID: String?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("新增考点")
                .font(.system(size: 14, weight: .semibold))
            Text("名称：\(target.name)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            ScrollView {
                VStack(spacing: 0) {
                    destinationRow(title: "通用（不分组）", groupID: nil)
                    ForEach(groups) { group in
                        destinationRow(title: group.name, groupID: group.id)
                    }
                }
            }
            .frame(maxHeight: 264)

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button("取消") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(NativeSecondaryButtonStyle())
                Button("确认") {
                    if let error = onCreate(selectedGroupID) {
                        errorMessage = error
                    } else {
                        onCancel()
                        dismiss()
                    }
                }
                .buttonStyle(NativePrimaryButtonStyle())
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear { selectedGroupID = nil }
    }

    private func destinationRow(title: String, groupID: String?) -> some View {
        Button { selectedGroupID = groupID } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedGroupID == groupID ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(selectedGroupID == groupID ? AppTheme.accent : Color.secondary)
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct LibraryKnowledgePointSearchInput<Chips: View>: View {
    @Binding var text: String
    let onSubmit: () -> Void
    let chips: Chips

    init(
        text: Binding<String>,
        onSubmit: @escaping () -> Void,
        @ViewBuilder chips: () -> Chips
    ) {
        _text = text
        self.onSubmit = onSubmit
        self.chips = chips()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                chips
                searchField
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 44)

            VStack(alignment: .leading, spacing: 4) {
                chips
                    .frame(maxWidth: .infinity, alignment: .leading)
                searchField
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
    }

    private var searchField: some View {
        TextField("搜索或新增考点", text: $text)
            .modifier(NativeDirectionalTextFieldNavigation())
            .font(.system(size: 14))
            .textFieldStyle(.plain)
            .frame(minWidth: 88, minHeight: 28)
            .layoutPriority(1)
            .onSubmit(onSubmit)
    }
}

private struct LibraryKnowledgePointGroupMoveTarget: Identifiable {
    let requestID = UUID()
    let reference: LibraryKnowledgePointReference
    let subject: String
    let module: String
    let typeID: String?
    let groups: [LibraryKnowledgePointGroup]
    var id: UUID { requestID }
}

private struct LibraryKnowledgePointGroupMoveDialog: ViewModifier {
    @Binding var target: LibraryKnowledgePointGroupMoveTarget?
    let onMove: (LibraryKnowledgePointGroupMoveTarget, String?) -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "修改分组",
            isPresented: Binding(
                get: { target != nil },
                set: { if !$0 { target = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("通用（不分组）") { move(to: nil) }
            ForEach(target?.groups ?? []) { group in
                Button(group.name) { move(to: group.id) }
            }
            Button("取消", role: .cancel) { target = nil }
        } message: {
            if let target { Text("将“\(target.reference.name)”移动到：") }
        }
    }

    private func move(to groupID: String?) {
        guard let target else { return }
        onMove(target, groupID)
        self.target = nil
    }
}

private enum LibraryKnowledgePointGroupMover {
    static func assign(
        _ target: LibraryKnowledgePointGroupMoveTarget,
        to groupID: String?,
        records: [StoredRecord],
        context: ModelContext
    ) -> String? {
        let name = target.reference.name
        let names: [String]
        if let typeID = target.typeID {
            names = VerbalReasoningKnowledgePointRepository.tags(
                module: target.module, typeID: typeID, records: records, subject: target.subject
            )
        } else {
            names = TagLibraryRepository.tags(kind: .knowledgePoint, module: target.module, records: records)
        }
        guard names.contains(name) else { return "考点目录已变化，分组未修改。请重新打开后再试。" }
        let groups = LibraryKnowledgePointGroupRepository.groups(
            subject: target.subject, module: target.module, typeID: target.typeID, records: records
        )
        guard groupID == nil || groups.contains(where: { $0.id == groupID }) else {
            return "目标分组已变化，考点未移动。请重新打开后再试。"
        }
        if LibraryKnowledgePointGroupRepository.groupID(
            for: name, subject: target.subject, module: target.module, typeID: target.typeID, records: records
        ) == groupID { return nil }
        do {
            try LibraryKnowledgePointGroupRepository.assign(
                name, to: groupID, subject: target.subject, module: target.module,
                typeID: target.typeID, records: records, context: context
            )
            return nil
        } catch {
            return "移动考点失败，请重试。"
        }
    }
}

/// Reuses the app's centered editor dialog, rather than embedding choices in the form.
struct LibraryTagSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let kind: ManagedTagKind
    let module: String
    var subject: String = ""
    @Binding var selection: String
    let onClose: () -> Void
    var selectionValues: Binding<[String]>? = nil
    var selectionReferences: Binding<[LibraryKnowledgePointReference]>? = nil
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil
    var titleOverride: String? = nil
    var maximumOverride: Int? = nil
    @State private var selected: [String] = []
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var selectedGroupID: String?
    @State private var showsOrder = false
    @State private var addDestinationTarget: LibraryKnowledgePointAddTarget?
    @State private var groupMoveTarget: LibraryKnowledgePointGroupMoveTarget?

    private var maximum: Int { maximumOverride ?? (kind == .knowledgePoint ? 3 : 1) }
    private var names: [String] {
        var values = TagLibraryRepository.tags(kind: kind, module: module, records: records)
        for value in selected where !values.contains(value) { values.append(value) }
        return values
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var knowledgePointGroups: [LibraryKnowledgePointGroup] {
        kind == .knowledgePoint
            ? LibraryKnowledgePointGroupRepository.groups(subject: subject, module: module, records: records)
            : []
    }

    var body: some View {
        NativeEditorDialog(title: "选择\(titleOverride ?? kind.rawValue)", canSave: selected.count <= maximum,
            actionTitle: "确定", onClose: onClose, onSave: {
                selection = orderedSelected.joined(separator: "、")
                selectionValues?.wrappedValue = orderedSelected
                updateSelectionReferences(orderedSelected)
                onClose()
            }, preferredSize: kind == .knowledgePoint ? CGSize(width: 420, height: 468) : nil,
            spacing: kind == .knowledgePoint ? 8 : 16) {
            if kind == .knowledgePoint {
                VStack(alignment: .leading, spacing: 8) {
                    Text("当前范围 · \(module)")
                        .font(.system(size: 12, weight: .semibold)).lineLimit(1).frame(height: 20, alignment: .leading)
                    searchAndAdd
                    if !knowledgePointGroups.isEmpty {
                        LibraryKnowledgePointGroupBar(groups: knowledgePointGroups, selectedID: selectedGroupID) {
                            selectedGroupID = $0
                        }
                    }
                    ScrollView(.vertical, showsIndicators: false) { knowledgePointTagContents }
                        .frame(maxHeight: .infinity)
                        .scrollDismissesKeyboard(.interactively)
                    HStack {
                        Text("已选 \(selected.count) 项").font(.system(size: 12)).foregroundStyle(.secondary)
                        Spacer()
                        if !selected.isEmpty {
                            Button("清空") { selected = [] }.font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
                        }
                    }.frame(height: 18)
                    if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
                }
                .frame(maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    searchAndAdd
                    HStack {
                        Text("已选 \(selected.count)/\(maximum) · 长按标签可重命名或删除")
                        Spacer()
                        Button("清空选择") { selected = [] }
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    ScrollView {
                        NativeTagFlow {
                            ForEach(names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }, id: \.self) { name in
                                Button { toggle(name) } label: {
                                    HStack(spacing: 4) {
                                        Text(name)
                                        if selected.contains(name) { Image(systemName: "checkmark") }
                                    }
                                    .font(.system(size: 12))
                                    .foregroundStyle(selected.contains(name) ? AppTheme.accent : Color.primary)
                                    .padding(.horizontal, 10).padding(.vertical, 9)
                                    .background(selected.contains(name) ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("重命名") { renaming = name; newName = name }
                                    Button("删除标签", role: .destructive) { deleting = name }
                                }
                            }
                        }
                    }.frame(maxHeight: 260)
                    if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
                }
            }
        }
        .onAppear {
            if let selectionReferences {
                selected = LibraryKnowledgePointReferencePolicy.displayNames(from: selectionReferences.wrappedValue.filter {
                    $0.module == module || $0.module == nil
                })
            } else {
                selected = selectionValues?.wrappedValue ?? split(selection)
            }
            selectedGroupID = knowledgePointGroups.first?.id
        }
        .alert("重命名标签", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("标签名称", text: $newName)
                .modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("同模块内已有记录的该标签会同步更新。") }
        .alert("删除标签？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从标签库及同模块已有记录中移除此标签，不删除题目。") }
        .sheet(isPresented: $showsOrder) {
            KnowledgePointOrderView(subject: subject, module: module, groupID: selectedGroupID)
        }
        .modifier(LibraryKnowledgePointGroupMoveDialog(target: $groupMoveTarget) { target, groupID in
            if let error = LibraryKnowledgePointGroupMover.assign(target, to: groupID, records: records, context: modelContext) {
                message = error
            }
        })
    }

    private func split(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        guard maximum > 1 else { return [value] }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if names.contains(trimmed) { return [trimmed] }
        let pieces = value.split(whereSeparator: { "、,，".contains($0) }).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return pieces.count > 1 && pieces.allSatisfy(names.contains) ? pieces : [trimmed]
    }

    @ViewBuilder private var selectedTagChips: some View {
        if kind == .knowledgePoint, !selected.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selected, id: \.self) { name in
                        Button {
                            selected.removeAll { $0 == name }
                        } label: {
                            HStack(spacing: 5) {
                                Text(name).lineLimit(1)
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10, weight: .medium))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(AppTheme.accent.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除已选考点：\(name)")
                    }
                }
            }
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        }
    }
    private var orderedSelected: [String] {
        guard kind == .knowledgePoint else { return selected }
        return names.filter { selected.contains($0) }
    }

    private func updateSelectionReferences(_ values: [String]) {
        guard kind == .knowledgePoint, let selectionReferences else { return }
        let existing = selectionReferences.wrappedValue
        let retained = existing.filter { reference in
            if reference.module == module { return false }
            if reference.module == nil { return !values.contains(reference.name) }
            return true
        }
        let selectedReferences = values.map { name in
            existing.first(where: {
                $0.name == name && ($0.module == module || $0.module == nil)
            }) ?? LibraryKnowledgePointReference(module: module, name: name)
        }
        selectionReferences.wrappedValue = LibraryKnowledgePointReferencePolicy.uniqueReferences(
            retained + selectedReferences
        )
    }

    private var searchAndAdd: some View {
        HStack(spacing: 8) {
            if kind == .knowledgePoint {
                LibraryKnowledgePointSearchInput(text: $search, onSubmit: beginAddTag) {
                    selectedTagChips
                }
            } else {
                TextField("搜索或输入新\(titleOverride ?? kind.rawValue)", text: $search)
                    .textFieldStyle(NativeTextFieldStyle())
                    .onSubmit(addTag)
            }
            Button("新增", action: beginAddTag)
                .font(.system(size: 12, weight: .semibold))
                .disabled(query.isEmpty || names.contains(query))
                .popover(item: $addDestinationTarget, arrowEdge: .top) { target in
                    LibraryKnowledgePointAddDestinationPopover(
                        target: target,
                        groups: LibraryKnowledgePointGroupRepository.groups(
                            subject: target.subject, module: target.module, records: records
                        ),
                        onCreate: { groupID in createKnowledgePoint(target, groupID: groupID) },
                        onCancel: { addDestinationTarget = nil }
                    )
                    .presentationCompactAdaptation(.popover)
                }
        }
    }

    @ViewBuilder
    private var knowledgePointTagContents: some View {
        let filtered = names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        if !query.isEmpty || knowledgePointGroups.isEmpty {
            knowledgePointTagCollection(filtered, groupID: selectedGroupID)
        } else {
            let selectedGroupNames = LibraryKnowledgePointGroupRepository.names(
                in: selectedGroupID, allNames: names, subject: subject, module: module, records: records
            )
            if selectedGroupNames.isEmpty {
                Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                knowledgePointTagCollection(selectedGroupNames, groupID: selectedGroupID)
            }
            let ungrouped = LibraryKnowledgePointGroupRepository.names(
                in: nil, allNames: names, subject: subject, module: module, records: records
            )
            if !ungrouped.isEmpty {
                Text("未分组").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 2)
                knowledgePointTagCollection(ungrouped, groupID: nil)
            }
        }
    }

    private func knowledgePointTagCollection(_ values: [String], groupID: String?) -> some View {
        let items = values.map {
            LibraryKnowledgePointTagItem(
                reference: LibraryKnowledgePointReference(module: module, name: $0),
                title: $0,
                isSelected: selected.contains($0)
            )
        }
        return LibraryKnowledgePointTagCollection(
            items: items,
            allowsReordering: query.isEmpty,
            onToggle: { toggle($0.name) },
            onReorder: { references in
                do {
                    try TagLibraryRepository.reorderKnowledgePoints(
                        references.map(\.name), module: module, groupID: groupID, subject: subject,
                        records: records, context: modelContext
                    )
                    return true
                } catch {
                    message = "排序未保存"
                    return false
                }
            },
            onRename: { renaming = $0.name; newName = $0.name },
            onMoveGroup: { reference in
                let targetModule = reference.module ?? module
                groupMoveTarget = LibraryKnowledgePointGroupMoveTarget(
                    reference: reference,
                    subject: subject,
                    module: targetModule,
                    typeID: nil,
                    groups: LibraryKnowledgePointGroupRepository.groups(
                        subject: subject, module: targetModule, records: records
                    )
                )
            },
            onDelete: { deleting = $0.name },
            onAdjustOrder: { _ in showsOrder = true }
        )
        .id("tag-picker|\(module)|\(groupID ?? "ungrouped")|\(query.isEmpty ? "browse" : "search")")
    }
    private func toggle(_ name: String) {
        message = nil
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else if maximum == 1 { selected = [name] }
        else if selected.count < maximum { selected.append(name) }
        else { message = "最多选择 \(maximum) 个\(titleOverride ?? kind.rawValue)" }
    }

    private func beginAddTag() {
        guard kind == .knowledgePoint else { addTag(); return }
        let value = query
        guard !value.isEmpty, !names.contains(value) else { return }
        let target = LibraryKnowledgePointAddTarget(name: value, subject: subject, module: module, typeID: nil)
        if knowledgePointGroups.isEmpty {
            if let error = createKnowledgePoint(target, groupID: nil) { message = error }
        } else {
            addDestinationTarget = target
        }
    }

    private func createKnowledgePoint(_ target: LibraryKnowledgePointAddTarget, groupID: String?) -> String? {
        let currentGroups = LibraryKnowledgePointGroupRepository.groups(
            subject: target.subject, module: target.module, records: records
        )
        guard groupID == nil || currentGroups.contains(where: { $0.id == groupID }) else {
            return "目标分组已变化，请重新选择。"
        }
        guard !target.name.isEmpty,
              !TagLibraryRepository.tags(kind: .knowledgePoint, module: target.module, records: records).contains(target.name) else {
            return "该来源中已有同名考点。"
        }
        do {
            try TagLibraryRepository.add(
                target.name, kind: .knowledgePoint, module: target.module, records: records,
                context: modelContext, knowledgePointGroupID: groupID, subject: target.subject
            )
            if !selected.contains(target.name) { selected.append(target.name) }
            search = ""
            return nil
        } catch {
            return "考点保存失败，请重试。"
        }
    }

    private func addTag() {
        guard kind != .knowledgePoint else { beginAddTag(); return }
        let value = query
        guard !value.isEmpty, !names.contains(value) else { return }
        do {
            try TagLibraryRepository.add(
                value, kind: kind, module: module, records: records, context: modelContext,
                knowledgePointGroupID: kind == .knowledgePoint ? selectedGroupID : nil,
                subject: subject
            )
            toggle(value)
            search = ""
        } catch { message = "标签保存失败，请重试" }
    }
    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与其他标签重复"; return
        }
        do {
            let result = try TagLibraryRepository.rename(old, to: value, kind: kind, module: module, subject: subject, records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map { $0 == old ? value : $0 }
            selectionValues?.wrappedValue = selected
            selection = selected.joined(separator: "、")
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }
    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: kind, module: module, subject: subject, records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0 == name }
            selectionValues?.wrappedValue = selected
            selection = selected.joined(separator: "、")
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct QuantityQuestionTypeSelectionDialog: View {
    @Query private var records: [StoredRecord]
    @Binding var selection: String
    let onClose: () -> Void

    private var questionTypes: [String] { QuantityQuestionTypeRepository.types(records: records) }

    var body: some View {
        NativeEditorDialog(
            title: "选择题型",
            canSave: true,
            actionTitle: "完成",
            onClose: onClose,
            onSave: onClose
        ) {
            VStack(alignment: .leading, spacing: 10) {
                Text("题型")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                if questionTypes.isEmpty {
                    Text("暂无题型，请先前往设置 → 数量题型管理中新增。")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                } else {
                    NativeTagFlow(spacing: 7) {
                        ForEach(questionTypes, id: \.self) { type in
                            Button {
                                selection = selection == type ? "" : type
                                onClose()
                            } label: {
                                HStack(spacing: 4) {
                                    Text(type)
                                    if selection == type { Image(systemName: "checkmark") }
                                }
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selection == type ? AppTheme.accent : Color.primary)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(
                                    selection == type ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                    in: Capsule()
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !selection.isEmpty {
                    Button("清除题型") { selection = ""; onClose() }
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(AppTheme.danger)
                }
            }
        }
    }
}

struct QuantityKnowledgePointSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let currentType: String
    @Binding var selection: String
    let onClose: () -> Void
    var selectionValues: Binding<[String]>? = nil
    var selectionReferences: Binding<[LibraryKnowledgePointReference]>? = nil
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil

    @State private var selected: [LibraryKnowledgePointReference] = []
    @State private var browsingType = ""
    @State private var showsCrossType = false
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var selectedGroupID: String?
    @State private var managingType: String?
    @State private var orderTarget: LibraryKnowledgePointOrderTarget?
    @State private var addDestinationTarget: LibraryKnowledgePointAddTarget?
    @State private var groupMoveTarget: LibraryKnowledgePointGroupMoveTarget?

    private var activeType: String { browsingType.isEmpty ? currentType : browsingType }
    private var questionTypes: [String] { QuantityQuestionTypeRepository.types(records: records) }
    private var names: [String] {
        TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
    }
    private var allKnownNames: Set<String> {
        Set((questionTypes + [currentType]).flatMap {
            TagLibraryRepository.tags(kind: .knowledgePoint, module: $0, records: records)
        })
    }
    private var groups: [LibraryKnowledgePointGroup] {
        LibraryKnowledgePointGroupRepository.groups(subject: "数量关系", module: activeType, records: records)
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NativeEditorDialog(
            title: "选择考点",
            canSave: true,
            actionTitle: "确定",
            onClose: onClose,
            onSave: {
                selectionReferences?.wrappedValue = orderedSelected
                selectionValues?.wrappedValue = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected)
                selection = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected).joined(separator: "、")
                onClose()
            },
            preferredSize: CGSize(width: 420, height: 468),
            spacing: 8
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showsCrossType ? "跨题型 · \(activeType)" : "当前题型 · \(currentType)")
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Button(showsCrossType ? "返回当前题型" : "＋ 跨题型选择") {
                        if showsCrossType {
                            showsCrossType = false
                            browsingType = currentType
                        } else {
                            showsCrossType = true
                            browsingType = questionTypes.first(where: { $0 != currentType }) ?? currentType
                        }
                        search = ""
                    }
                    .font(.system(size: 11, weight: .semibold))
                }

                if showsCrossType {
                    NativeTagFlow(spacing: 6) {
                        ForEach(questionTypes.filter { $0 != currentType }, id: \.self) { type in
                            Button { browsingType = type; search = "" } label: {
                                Text(type).font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(activeType == type ? AppTheme.accent : Color.primary)
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background(activeType == type ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                }

                HStack(spacing: 8) {
                    LibraryKnowledgePointSearchInput(text: $search, onSubmit: beginAddTag) {
                        selectedTagChips
                    }
                    Button("新增", action: beginAddTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || activeType.isEmpty || names.contains(query))
                        .popover(item: $addDestinationTarget, arrowEdge: .top) { target in
                            LibraryKnowledgePointAddDestinationPopover(
                                target: target,
                                groups: LibraryKnowledgePointGroupRepository.groups(
                                    subject: target.subject, module: target.module, records: records
                                ),
                                onCreate: { groupID in createKnowledgePoint(target, groupID: groupID) },
                                onCancel: { addDestinationTarget = nil }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                }

                if !groups.isEmpty {
                    LibraryKnowledgePointGroupBar(groups: groups, selectedID: selectedGroupID) { selectedGroupID = $0 }
                }
                ScrollView(.vertical, showsIndicators: false) { groupedTagContents }
                    .frame(maxHeight: .infinity)
                    .scrollDismissesKeyboard(.interactively)
                HStack {
                    Text("已选 \(selected.count) 项").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if !selected.isEmpty {
                        Button("清空") { selected = [] }.font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
                    }
                }.frame(height: 18)
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            selected = selectionReferences?.wrappedValue
                ?? (selectionValues?.wrappedValue ?? parseSelection(selection)).map {
                    LibraryKnowledgePointReference(module: currentType, name: $0)
                }
            browsingType = currentType
            selectedGroupID = groups.first?.id
        }
        .onChange(of: browsingType) { _, _ in selectedGroupID = groups.first?.id }
        .alert("重命名考点", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("考点名称", text: $newName)
                .modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("当前题型已有记录中的该考点会同步更新。") }
        .alert("删除考点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从考点库及当前题型已有记录中移除此考点，不删除题目。") }
        .sheet(item: $orderTarget) { target in
            KnowledgePointOrderView(subject: target.subject, module: target.module, groupID: target.groupID)
        }
        .modifier(LibraryKnowledgePointGroupMoveDialog(target: $groupMoveTarget) { target, groupID in
            if let error = LibraryKnowledgePointGroupMover.assign(target, to: groupID, records: records, context: modelContext) {
                message = error
            }
        })
    }

    private func parseSelection(_ value: String) -> [String] {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if allKnownNames.contains(trimmed) { return [trimmed] }
        let pieces = value.split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard pieces.count > 1,
              pieces.allSatisfy({ !$0.isEmpty && allKnownNames.contains($0) }),
              Set(pieces).count == pieces.count else { return [trimmed] }
        return pieces
    }

    @ViewBuilder
    private var selectedTagChips: some View {
        if !selected.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selected) { reference in
                        Button { selected.removeAll { $0 == reference } } label: {
                            HStack(spacing: 5) {
                                Text(reference.module == currentType ? reference.name : "\(reference.module ?? "旧题型") · \(reference.name)").lineLimit(1)
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10, weight: .medium))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(AppTheme.accent.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除已选考点：\(reference.module ?? "旧题型") · \(reference.name)")
                    }
                }
            }
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        }
    }

    private func toggle(_ reference: LibraryKnowledgePointReference) {
        if selected.contains(reference) { selected.removeAll { $0 == reference } }
        else { selected.append(reference) }
    }

    @ViewBuilder
    private var groupedTagContents: some View {
        let available = names.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
        if !query.isEmpty || groups.isEmpty {
            tagCollection(available, groupID: selectedGroupID)
        } else {
            let selectedNames = LibraryKnowledgePointGroupRepository.names(
                in: selectedGroupID, allNames: names, subject: "数量关系", module: activeType, records: records
            )
            if selectedNames.isEmpty {
                Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                tagCollection(selectedNames, groupID: selectedGroupID)
            }
            let ungrouped = LibraryKnowledgePointGroupRepository.names(
                in: nil, allNames: names, subject: "数量关系", module: activeType, records: records
            )
            if !ungrouped.isEmpty {
                Text("未分组").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.top, 2)
                tagCollection(ungrouped, groupID: nil)
            }
        }
    }

    private func tagCollection(_ values: [String], groupID: String?) -> some View {
        let items = values.map { name in
            let reference = LibraryKnowledgePointReference(module: activeType, name: name)
            return LibraryKnowledgePointTagItem(
                reference: reference,
                title: name,
                isSelected: selected.contains(reference)
            )
        }
        return LibraryKnowledgePointTagCollection(
            items: items,
            allowsReordering: query.isEmpty,
            onToggle: toggle,
            onReorder: { references in
                do {
                    try TagLibraryRepository.reorderKnowledgePoints(
                        references.map(\.name), module: activeType, groupID: groupID, subject: "数量关系",
                        records: records, context: modelContext
                    )
                    return true
                } catch {
                    message = "排序未保存"
                    return false
                }
            },
            onRename: { reference in
                managingType = reference.module ?? activeType
                renaming = reference.name
                newName = reference.name
            },
            onMoveGroup: { reference in
                let targetModule = reference.module ?? activeType
                groupMoveTarget = LibraryKnowledgePointGroupMoveTarget(
                    reference: reference,
                    subject: "数量关系",
                    module: targetModule,
                    typeID: nil,
                    groups: LibraryKnowledgePointGroupRepository.groups(
                        subject: "数量关系", module: targetModule, records: records
                    )
                )
            },
            onDelete: { reference in
                managingType = reference.module ?? activeType
                deleting = reference.name
            },
            onAdjustOrder: { _ in
                orderTarget = LibraryKnowledgePointOrderTarget(
                    subject: "数量关系", module: activeType, typeID: nil, groupID: groupID
                )
            }
        )
        .id("quantity-picker|\(activeType)|\(groupID ?? "ungrouped")|\(query.isEmpty ? "browse" : "search")")
    }

    private var orderedSelected: [LibraryKnowledgePointReference] {
        let currentNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
        let current = currentNames.compactMap { name in
            selected.first(where: { $0.module == activeType && $0.name == name })
        }
        return current + selected.filter { $0.module != activeType || !currentNames.contains($0.name) }
    }

    private func addTag() {
        beginAddTag()
    }

    private func beginAddTag() {
        guard !query.isEmpty, !activeType.isEmpty else { return }
        let target = LibraryKnowledgePointAddTarget(
            name: query, subject: "数量关系", module: activeType, typeID: nil
        )
        if groups.isEmpty {
            if let error = createKnowledgePoint(target, groupID: nil) { message = error }
        } else {
            addDestinationTarget = target
        }
    }

    private func createKnowledgePoint(_ target: LibraryKnowledgePointAddTarget, groupID: String?) -> String? {
        let currentGroups = LibraryKnowledgePointGroupRepository.groups(
            subject: target.subject, module: target.module, records: records
        )
        guard groupID == nil || currentGroups.contains(where: { $0.id == groupID }) else {
            return "目标分组已变化，请重新选择。"
        }
        let existingNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: target.module, records: records)
        guard !target.name.isEmpty, !existingNames.contains(target.name) else { return "该题型中已有同名考点。" }
        do {
            try TagLibraryRepository.add(
                target.name, kind: .knowledgePoint, module: target.module, records: records,
                context: modelContext, knowledgePointGroupID: groupID, subject: target.subject
            )
            let reference = LibraryKnowledgePointReference(module: target.module, name: target.name)
            if !selected.contains(reference) { selected.append(reference) }
            search = ""
            return nil
        } catch {
            return "考点保存失败，请重试。"
        }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let targetType = managingType ?? activeType
        let targetNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: targetType, records: records)
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !targetNames.contains(value) else {
            message = "名称不能为空或与其他考点重复"
            return
        }
        do {
            let result = try TagLibraryRepository.rename(old, to: value, kind: .knowledgePoint, module: targetType, subject: "数量关系", records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map {
                $0.module == targetType && $0.name == old
                    ? LibraryKnowledgePointReference(module: targetType, name: value)
                    : $0
            }
            selectionReferences?.wrappedValue = orderedSelected
            selectionValues?.wrappedValue = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected)
            selection = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected).joined(separator: "、")
            renaming = nil
            managingType = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        let targetType = managingType ?? activeType
        do {
            let result = try TagLibraryRepository.delete(name, kind: .knowledgePoint, module: targetType, subject: "数量关系", records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0.module == targetType && $0.name == name }
            selectionReferences?.wrappedValue = orderedSelected
            selectionValues?.wrappedValue = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected)
            selection = LibraryKnowledgePointReferencePolicy.displayNames(from: orderedSelected).joined(separator: "、")
            deleting = nil
            managingType = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct VerbalReasoningKnowledgePointSelectionDialog: View {
    private static let legacyTypeSelection = "__legacy_verbal_knowledge_points__"
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    var subject: String = "言语理解"
    let currentModule: String
    let currentTypeID: String?
    @Binding var selection: [LibraryKnowledgePointReference]
    @Binding var legacyDisplaySelection: String
    let onClose: () -> Void
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil
    var onCommit: (([LibraryKnowledgePointReference]) -> String?)? = nil

    @State private var selected: [LibraryKnowledgePointReference] = []
    @State private var browsingTypeSelection = ""
    @State private var showsCrossType = false
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var selectedGroupID: String?
    @State private var managingReference: LibraryKnowledgePointReference?
    @State private var orderTarget: LibraryKnowledgePointOrderTarget?
    @State private var addDestinationTarget: LibraryKnowledgePointAddTarget?
    @State private var groupMoveTarget: LibraryKnowledgePointGroupMoveTarget?

    private var typeLabel: String { subject == "资料分析" ? "错误类型" : "题型" }
    private var deletedTypeLabel: String { "\(typeLabel)已删除" }
    private var types: [LibraryErrorType] {
        guard let typeSubject = LibraryErrorTypeSubject(rawValue: subject) else { return [] }
        return LibraryErrorTypeRepository.types(for: typeSubject, records: records)
            .filter { $0.isAvailable(in: currentModule) }
    }
    private var activeTypeID: String? {
        guard !browsingTypeSelection.isEmpty, browsingTypeSelection != Self.legacyTypeSelection else { return nil }
        return browsingTypeSelection
    }
    private var activeTypeName: String {
        guard let activeTypeID else { return "旧考点" }
        return types.first(where: { $0.id == activeTypeID })?.name ?? deletedTypeLabel
    }
    private var currentTypeTitle: String {
        guard let currentTypeID else { return "\(typeLabel)未设置" }
        let name = types.first(where: { $0.id == currentTypeID })?.name ?? deletedTypeLabel
        return "当前\(typeLabel) · \(name)"
    }
    private var names: [String] {
        guard let activeTypeID else {
            return TagLibraryRepository.tags(kind: .knowledgePoint, module: currentModule, records: records)
        }
        return VerbalReasoningKnowledgePointRepository.tags(
            module: currentModule,
            typeID: activeTypeID,
            records: records,
            subject: subject
        )
    }
    private var query: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var filteredNames: [String] {
        guard activeTypeID != nil else { return [] }
        var values = names
        for reference in selected where reference.module == currentModule
            && reference.typeID == activeTypeID && !values.contains(reference.name) {
            values.append(reference.name)
        }
        return values.filter { query.isEmpty || $0.localizedCaseInsensitiveContains(query) }
    }
    private var legacyNames: [String] {
        let selectedNames = selected.compactMap { reference -> String? in
            guard (reference.module == currentModule || reference.module == nil), reference.typeID == nil else { return nil }
            return reference.name
        }
        let available = activeTypeID == nil
            ? names
            : selectedNames
        return available.reduce(into: []) { values, name in
            if !values.contains(name), query.isEmpty || name.localizedCaseInsensitiveContains(query) {
                values.append(name)
            }
        }
    }
    private var groups: [LibraryKnowledgePointGroup] {
        LibraryKnowledgePointGroupRepository.groups(subject: subject, module: currentModule, typeID: activeTypeID, records: records)
    }
    private var browsableTypes: [LibraryErrorType] {
        types.filter { showsCrossType ? $0.id != currentTypeID : $0.id == currentTypeID }
    }

    var body: some View {
        NativeEditorDialog(
            title: "选择考点",
            canSave: true,
            actionTitle: "确定",
            onClose: onClose,
            onSave: commitSelection,
            preferredSize: CGSize(width: 420, height: 468),
            spacing: 8
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(showsCrossType
                         ? "跨\(typeLabel) · \(activeTypeName)"
                         : currentTypeTitle)
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if showsCrossType || currentTypeID == nil || types.contains(where: { $0.id != currentTypeID }) {
                        Button(showsCrossType
                               ? (currentTypeID == nil ? "返回旧考点" : "返回当前\(typeLabel)")
                               : (currentTypeID == nil ? "选择\(typeLabel)" : "＋ 跨\(typeLabel)选择")) {
                        if showsCrossType {
                            showsCrossType = false
                            browsingTypeSelection = currentTypeID ?? Self.legacyTypeSelection
                        } else {
                            showsCrossType = true
                            browsingTypeSelection = types.first(where: { $0.id != currentTypeID })?.id
                                ?? types.first?.id
                                ?? Self.legacyTypeSelection
                        }
                        search = ""
                    }
                    .font(.system(size: 11, weight: .semibold))
                    }
                }

                if showsCrossType {
                    NativeTagFlow(spacing: 6) {
                        ForEach(browsableTypes) { type in
                            Button {
                                browsingTypeSelection = type.id
                                search = ""
                            } label: {
                                Text(type.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(activeTypeID == type.id ? AppTheme.accent : Color.primary)
                                    .padding(.horizontal, 9).frame(height: 28)
                                    .background(
                                        activeTypeID == type.id ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                        in: Capsule()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    if types.isEmpty {
                        Text("暂无\(typeLabel)，请先前往设置 → \(LibraryErrorTypeSubject(rawValue: subject)?.managementTitle ?? subject + typeLabel + "管理")中创建。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    LibraryKnowledgePointSearchInput(text: $search, onSubmit: beginAddTag) {
                        selectedReferenceChips
                    }
                    Button("新增", action: beginAddTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || names.contains(query) || currentModule.isEmpty)
                        .popover(item: $addDestinationTarget, arrowEdge: .top) { target in
                            LibraryKnowledgePointAddDestinationPopover(
                                target: target,
                                groups: LibraryKnowledgePointGroupRepository.groups(
                                    subject: target.subject, module: target.module,
                                    typeID: target.typeID, records: records
                                ),
                                onCreate: { groupID in createKnowledgePoint(target, groupID: groupID) },
                                onCancel: { addDestinationTarget = nil }
                            )
                            .presentationCompactAdaptation(.popover)
                        }
                }

                if !groups.isEmpty {
                    LibraryKnowledgePointGroupBar(groups: groups, selectedID: selectedGroupID) {
                        selectedGroupID = $0
                    }
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        if !filteredNames.isEmpty {
                            if !query.isEmpty || groups.isEmpty {
                                tagCollection(filteredNames, groupID: selectedGroupID, typeID: activeTypeID)
                            } else {
                                let groupNames = LibraryKnowledgePointGroupRepository.names(
                                    in: selectedGroupID, allNames: names, subject: subject, module: currentModule,
                                    typeID: activeTypeID, records: records
                                )
                                if groupNames.isEmpty {
                                    Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
                                } else {
                                    tagCollection(groupNames, groupID: selectedGroupID, typeID: activeTypeID)
                                }
                                let ungrouped = LibraryKnowledgePointGroupRepository.names(
                                    in: nil, allNames: names, subject: subject, module: currentModule,
                                    typeID: activeTypeID, records: records
                                )
                                let selectedOnly = filteredNames.filter { !names.contains($0) }
                                let ungroupedAndExisting = Array(Set(ungrouped + selectedOnly)).sorted {
                                    let left = names.firstIndex(of: $0) ?? .max
                                    let right = names.firstIndex(of: $1) ?? .max
                                    return left == right ? $0 < $1 : left < right
                                }
                                if !ungroupedAndExisting.isEmpty {
                                    Text("未分组").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                                    tagCollection(ungroupedAndExisting, groupID: nil, typeID: activeTypeID)
                                }
                            }
                        }
                        if !legacyNames.isEmpty {
                            Text("旧考点")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.secondary)
                            legacyTagContents
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                .scrollDismissesKeyboard(.interactively)
                HStack {
                    Text("已选 \(selected.count) 项").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    if !selected.isEmpty {
                        Button("清空") { selected = [] }.font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.accent)
                    }
                }.frame(height: 18)
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(AppTheme.danger) }
            }
            .frame(maxHeight: .infinity)
        }
        .onAppear {
            let available = Set(TagLibraryRepository.tags(kind: .knowledgePoint, module: currentModule, records: records))
            selected = LibraryKnowledgePointReferencePolicy.resolvingLocalReferences(
                selection,
                currentModule: currentModule,
                availableNames: available
            )
            browsingTypeSelection = currentTypeID ?? Self.legacyTypeSelection
            selectedGroupID = groups.first?.id
        }
        .onChange(of: browsingTypeSelection) { _, _ in selectedGroupID = groups.first?.id }
        .sheet(item: $orderTarget) { target in
            KnowledgePointOrderView(subject: target.subject, module: target.module, typeID: target.typeID, groupID: target.groupID)
        }
        .modifier(LibraryKnowledgePointGroupMoveDialog(target: $groupMoveTarget) { target, groupID in
            if let error = LibraryKnowledgePointGroupMover.assign(target, to: groupID, records: records, context: modelContext) {
                message = error
            }
        })
        .alert("重命名考点", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("考点名称", text: $newName).modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("当前\(typeLabel)中的该考点会同步更新。") }
        .alert("删除考点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从考点库和引用该来源考点的错题中移除。") }
    }

    private func selectedTitle(for reference: LibraryKnowledgePointReference) -> String {
        if let sourceModule = reference.module, sourceModule != currentModule {
            let origin: String
            if let typeID = reference.typeID {
                let typeSubject = LibraryErrorTypeSubject(rawValue: subject) ?? .verbalReasoning
                origin = LibraryErrorTypeRepository.types(for: typeSubject, records: records)
                    .first(where: { $0.module == sourceModule && $0.id == typeID })?.name ?? deletedTypeLabel
            } else {
                origin = "旧考点"
            }
            return "\(sourceModule) · \(origin) · \(reference.name)"
        }
        if reference.typeID == nil { return "旧考点 · \(reference.name)" }
        let typeName = types.first(where: { $0.id == reference.typeID })?.name ?? deletedTypeLabel
        guard selected.filter({ $0.name == reference.name }).count > 1 else { return "\(typeName) · \(reference.name)" }
        return "\(reference.module ?? currentModule) · \(typeName) · \(reference.name)"
    }

    @ViewBuilder private var selectedReferenceChips: some View {
        if !selected.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(selected) { reference in
                        Button { selected.removeAll { $0 == reference } } label: {
                            HStack(spacing: 5) {
                                Text(selectedTitle(for: reference)).lineLimit(1)
                                Image(systemName: "xmark.circle.fill").font(.system(size: 10, weight: .medium))
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppTheme.accent)
                            .padding(.horizontal, 8)
                            .frame(height: 28)
                            .background(AppTheme.accent.opacity(0.08), in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除已选考点：\(selectedTitle(for: reference))")
                    }
                }
            }
            .frame(minWidth: 72, maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        }
    }

    private func tagCollection(_ values: [String], groupID: String?, typeID: String?) -> some View {
        let libraryNames = typeID.map {
            VerbalReasoningKnowledgePointRepository.tags(module: currentModule, typeID: $0, records: records, subject: subject)
        } ?? TagLibraryRepository.tags(kind: .knowledgePoint, module: currentModule, records: records)
        let items = values.map { name in
            let reference = selected.first(where: {
                $0.name == name && $0.typeID == typeID && ($0.module == currentModule || $0.module == nil)
            }) ?? LibraryKnowledgePointReference(module: currentModule, typeID: typeID, name: name)
            return LibraryKnowledgePointTagItem(
                reference: reference,
                title: selected.filter { $0.name == name }.count > 1 ? selectedTitle(for: reference) : name,
                isSelected: selected.contains(reference)
            )
        }
        return LibraryKnowledgePointTagCollection(
            items: items,
            allowsReordering: query.isEmpty && values.allSatisfy(libraryNames.contains),
            onToggle: toggle,
            onReorder: { references in
                do {
                    if let typeID {
                        try VerbalReasoningKnowledgePointRepository.reorder(
                            references.map(\.name), module: currentModule, typeID: typeID,
                            records: records, context: modelContext, groupID: groupID, subject: subject
                        )
                    } else {
                        try TagLibraryRepository.reorderKnowledgePoints(
                            references.map(\.name), module: currentModule, groupID: groupID, subject: subject,
                            records: records, context: modelContext
                        )
                    }
                    return true
                } catch {
                    message = "排序未保存"
                    return false
                }
            },
            onRename: { reference in
                managingReference = reference
                renaming = reference.name
                newName = reference.name
            },
            onDelete: { reference in
                managingReference = reference
                deleting = reference.name
            },
            onMoveGroup: { reference in
                beginGroupMove(reference, module: reference.module ?? currentModule, typeID: reference.typeID)
            },
            onAdjustOrder: { reference in
                orderTarget = LibraryKnowledgePointOrderTarget(
                    subject: subject,
                    module: reference.module ?? currentModule,
                    typeID: reference.typeID,
                    groupID: groupID
                )
            }
        )
        .id("typed-picker|\(subject)|\(currentModule)|\(typeID ?? "legacy")|\(groupID ?? "ungrouped")|\(query.isEmpty ? "browse" : "search")")
    }

    @ViewBuilder
    private var legacyTagContents: some View {
        if activeTypeID == nil, !groups.isEmpty {
            let groupedNames = LibraryKnowledgePointGroupRepository.names(
                in: selectedGroupID, allNames: legacyNames, subject: subject, module: currentModule,
                records: records
            )
            if groupedNames.isEmpty {
                Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                tagCollection(groupedNames, groupID: selectedGroupID, typeID: nil)
            }
            let ungrouped = LibraryKnowledgePointGroupRepository.names(
                in: nil, allNames: legacyNames, subject: subject, module: currentModule, records: records
            )
            if !ungrouped.isEmpty {
                Text("未分组").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                tagCollection(ungrouped, groupID: nil, typeID: nil)
            }
        } else {
            let items = legacyNames.map { name in
                let reference = selected.first(where: {
                    $0.name == name && $0.typeID == nil && ($0.module == currentModule || $0.module == nil)
                }) ?? LibraryKnowledgePointReference(module: currentModule, name: name)
                return LibraryKnowledgePointTagItem(
                    reference: reference,
                    title: name,
                    isSelected: selected.contains(reference)
                )
            }
            LibraryKnowledgePointTagCollection(
                items: items,
                allowsReordering: query.isEmpty,
                onToggle: toggle,
                onReorder: { references in
                    do {
                        try TagLibraryRepository.reorderKnowledgePoints(
                            references.map(\.name), module: currentModule, subject: subject,
                            records: records, context: modelContext
                        )
                        return true
                    } catch { message = "排序未保存"; return false }
                },
                onRename: { reference in
                    managingReference = reference
                    renaming = reference.name
                    newName = reference.name
                },
                onDelete: { reference in
                    managingReference = reference
                    deleting = reference.name
                },
                onMoveGroup: { reference in
                    beginGroupMove(reference, module: reference.module ?? currentModule, typeID: reference.typeID)
                },
                onAdjustOrder: { reference in
                    orderTarget = LibraryKnowledgePointOrderTarget(
                        subject: subject, module: reference.module ?? currentModule, typeID: nil, groupID: nil
                    )
                }
            )
            .id("verbal-legacy-picker|\(currentModule)")
        }
    }

    private func toggle(_ reference: LibraryKnowledgePointReference) {
        if selected.contains(reference) { selected.removeAll { $0 == reference } }
        else { selected.append(reference) }
    }

    private func beginGroupMove(
        _ reference: LibraryKnowledgePointReference,
        module: String,
        typeID: String?
    ) {
        groupMoveTarget = LibraryKnowledgePointGroupMoveTarget(
            reference: reference,
            subject: subject,
            module: module,
            typeID: typeID,
            groups: LibraryKnowledgePointGroupRepository.groups(
                subject: subject, module: module, typeID: typeID, records: records
            )
        )
    }

    private func commitSelection() {
        let values = LibraryKnowledgePointReferencePolicy.uniqueReferences(selected)
        if let error = onCommit?(values) {
            message = error
            return
        }
        selection = values
        legacyDisplaySelection = LibraryKnowledgePointReferencePolicy.displayNames(from: values).joined(separator: "、")
        onClose()
    }

    private func addTag() {
        beginAddTag()
    }

    private func beginAddTag() {
        guard !query.isEmpty, !currentModule.isEmpty, !names.contains(query) else { return }
        let target = LibraryKnowledgePointAddTarget(
            name: query, subject: subject, module: currentModule, typeID: activeTypeID
        )
        if groups.isEmpty {
            if let error = createKnowledgePoint(target, groupID: nil) { message = error }
        } else {
            addDestinationTarget = target
        }
    }

    private func createKnowledgePoint(_ target: LibraryKnowledgePointAddTarget, groupID: String?) -> String? {
        let currentGroups = LibraryKnowledgePointGroupRepository.groups(
            subject: target.subject, module: target.module, typeID: target.typeID, records: records
        )
        guard groupID == nil || currentGroups.contains(where: { $0.id == groupID }) else {
            return "目标分组已变化，请重新选择。"
        }
        let targetNames = target.typeID.map {
            VerbalReasoningKnowledgePointRepository.tags(
                module: target.module, typeID: $0, records: records, subject: target.subject
            )
        } ?? TagLibraryRepository.tags(kind: .knowledgePoint, module: target.module, records: records)
        guard !target.name.isEmpty, !targetNames.contains(target.name) else { return "该来源中已有同名考点。" }
        do {
            if let typeID = target.typeID {
                try VerbalReasoningKnowledgePointRepository.add(
                    target.name, module: target.module, typeID: typeID, records: records,
                    context: modelContext, groupID: groupID, subject: target.subject
                )
            } else {
                try TagLibraryRepository.add(
                    target.name, kind: .knowledgePoint, module: target.module, records: records,
                    context: modelContext, knowledgePointGroupID: groupID, subject: target.subject
                )
            }
            toggle(LibraryKnowledgePointReference(module: target.module, typeID: target.typeID, name: target.name))
            search = ""
            return nil
        } catch {
            return "考点保存失败，请重试。"
        }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let target = managingReference ?? LibraryKnowledgePointReference(module: currentModule, typeID: activeTypeID, name: old)
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetNames = target.typeID.map {
            VerbalReasoningKnowledgePointRepository.tags(module: target.module ?? currentModule, typeID: $0, records: records, subject: subject)
        } ?? TagLibraryRepository.tags(kind: .knowledgePoint, module: target.module ?? currentModule, records: records)
        guard !value.isEmpty, value != old, !targetNames.contains(value) else {
            message = "名称不能为空或与当前\(typeLabel)其他考点重复"
            return
        }
        do {
            let result: LibraryTagMutationResult
            if let typeID = target.typeID {
                result = try VerbalReasoningKnowledgePointRepository.rename(
                    old, to: value, module: target.module ?? currentModule, typeID: typeID, records: records, context: modelContext,
                    subject: subject
                )
            } else {
                result = try TagLibraryRepository.rename(
                    old, to: value, kind: .knowledgePoint, module: target.module ?? currentModule, subject: subject, records: records, context: modelContext
                )
            }
            onTagMutation?(result)
            selected = selected.map { reference in
                (reference.module == target.module || (reference.module == nil && target.module == currentModule))
                    && reference.typeID == target.typeID && reference.name == old
                    ? LibraryKnowledgePointReference(module: target.module ?? currentModule, typeID: target.typeID, name: value)
                    : reference
            }
            renaming = nil
            managingReference = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        let target = managingReference ?? LibraryKnowledgePointReference(module: currentModule, typeID: activeTypeID, name: name)
        do {
            let result: LibraryTagMutationResult
            if let typeID = target.typeID {
                result = try VerbalReasoningKnowledgePointRepository.delete(
                    name, module: target.module ?? currentModule, typeID: typeID, records: records, context: modelContext,
                    subject: subject
                )
            } else {
                result = try TagLibraryRepository.delete(
                    name, kind: .knowledgePoint, module: target.module ?? currentModule, subject: subject, records: records, context: modelContext
                )
            }
            onTagMutation?(result)
            selected.removeAll { $0.module == target.module && $0.typeID == target.typeID && $0.name == name }
            deleting = nil
            managingReference = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct LibraryRelationSelectionDialog: View {
    let collection: String
    let candidates: [StoredRecord]
    @Binding var selection: [String]
    let onClose: () -> Void
    var onCreateWord: (() -> Void)? = nil
    @State private var selected: [String] = []
    @State private var search = ""
    @State private var wordCategoryFilter: WordCategory?

    private let wordCategoryFilterOrder: [WordCategory] = [
        .idiomDefinition, .idiomComparison, .wordDefinition, .wordComparison
    ]

    var body: some View {
        NativeEditorDialog(title: dialogTitle,
            canSave: true, actionTitle: "确定", onClose: onClose, onSave: { selection = selected; onClose() }) {
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    TextField("搜索", text: $search).textFieldStyle(NativeTextFieldStyle())
                    if collection == "words", let onCreateWord {
                        Button(action: onCreateWord) {
                            Label("新建", systemImage: "plus")
                                .font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 10)
                                .frame(height: 38)
                                .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    Text("已选 \(selected.count) 项")
                    Spacer()
                    Button("清空关联") { selected = [] }
                }.font(.system(size: 11))
                if collection == "words" {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 7) {
                            ForEach(wordCategoryFilterOrder) { category in
                                let isSelected = wordCategoryFilter == category
                                Button {
                                    wordCategoryFilter = isSelected ? nil : category
                                } label: {
                                    Text(category.shortTitle)
                                        .font(.system(size: 11))
                                        .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
                                        .padding(.horizontal, 9)
                                        .frame(height: 31)
                                        .background(
                                            isSelected ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                            in: Capsule()
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredCandidates, id: \.compoundID) { record in
                            Button {
                                if selected.contains(record.recordID) { selected.removeAll { $0 == record.recordID } }
                                else if collection == "exams" { selected = [record.recordID] }
                                else { selected.append(record.recordID) }
                            } label: {
                                let snapshot = LibraryRecordSnapshot(record: record)
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        if collection == "errors" {
                                            Text(errorReferenceLine(snapshot))
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.secondary)
                                            Text(snapshot.title)
                                                .font(.system(size: 12))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(2)
                                        } else {
                                            Text(snapshot.title).font(.system(size: 13)).foregroundStyle(.primary).lineLimit(2)
                                        }
                                        if collection == "words" {
                                            Text(snapshot.tags.joined(separator: " · "))
                                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: selected.contains(record.recordID) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(AppTheme.accent)
                                }
                                .padding(.horizontal, 7)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                        if filteredCandidates.isEmpty {
                            VStack(spacing: 7) {
                                Text("暂无符合条件的关联内容")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                if collection == "words", let onCreateWord {
                                    Button(action: onCreateWord) {
                                        Label("直接新建词语", systemImage: "plus.circle")
                                            .font(.system(size: 12, weight: .medium))
                                    }
                                }
                            }
                            .padding(.vertical, 10)
                        }
                    }
                }
                .contentMargins(.trailing, 8, for: .scrollContent)
                .frame(maxHeight: 320)
            }
        }.onAppear { selected = selection }
    }

    private var filteredCandidates: [StoredRecord] {
        candidates.filter { record in
            guard LibraryRelationCandidateScope.includes(
                candidateCollection: record.collection,
                targetCollection: collection
            ) else { return false }
            let snapshot = LibraryRecordSnapshot(record: record)
            let matchesSearch = search.isEmpty || snapshot.searchableText.localizedCaseInsensitiveContains(search)
            let matchesCategory = collection != "words" || wordCategoryFilter == nil || snapshot.category == wordCategoryFilter?.rawValue
            return matchesSearch && matchesCategory
        }
    }

    private var dialogTitle: String {
        switch collection {
        case "exams": "来源套卷"
        case "notes": "关联笔记"
        case "errors": "关联错题"
        default: "关联词语"
        }
    }

    private func errorReferenceLine(_ snapshot: LibraryRecordSnapshot) -> String {
        let source = snapshot.questionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = snapshot.questionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = source.isEmpty ? "来源未填写" : source
        let numberText = number.isEmpty
            ? "题号未填写"
            : (number.hasPrefix("第") || number.hasSuffix("题") ? number : "第\(number)题")
        return "\(sourceText) · \(numberText)"
    }

}
