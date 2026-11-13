import SwiftData
import SwiftUI

/// Reuses the app's centered editor dialog, rather than embedding choices in the form.
struct LibraryTagSelectionDialog: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    let kind: ManagedTagKind
    let module: String
    var subject: String = ""
    @Binding var selection: String
    let onClose: () -> Void
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
            selected = split(selection)
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
    }

    private func split(_ value: String) -> [String] {
        guard !value.isEmpty else { return [] }
        return maximum > 1 ? value.split(whereSeparator: { "、,，".contains($0) }).map(String.init) : [value]
    }
    private var orderedSelected: [String] {
        guard kind == .knowledgePoint else { return selected }
        return names.filter { selected.contains($0) }
    }

    private var searchAndAdd: some View {
        HStack(spacing: 8) {
            if kind == .knowledgePoint {
                TextField("搜索或新增考点", text: $search)
                    .modifier(NativeDirectionalTextFieldNavigation())
                    .font(.system(size: 14))
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                    .onSubmit(addTag)
            } else {
                TextField("搜索或输入新\(titleOverride ?? kind.rawValue)", text: $search)
                    .textFieldStyle(NativeTextFieldStyle())
                    .onSubmit(addTag)
            }
            Button("新增", action: addTag)
                .font(.system(size: 12, weight: .semibold))
                .disabled(query.isEmpty || names.contains(query))
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
            }
        )
    }
    private func toggle(_ name: String) {
        message = nil
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else if maximum == 1 { selected = [name] }
        else if selected.count < maximum { selected.append(name) }
        else { message = "最多选择 \(maximum) 个\(titleOverride ?? kind.rawValue)" }
    }
    private func addTag() {
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
            selection = split(selection).map { $0 == old ? value : $0 }.joined(separator: "、")
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }
    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: kind, module: module, subject: subject, records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0 == name }
            selection = split(selection).filter { $0 != name }.joined(separator: "、")
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
    var onTagMutation: ((LibraryTagMutationResult) -> Void)? = nil

    @State private var selected: [String] = []
    @State private var browsingType = ""
    @State private var showsCrossType = false
    @State private var search = ""
    @State private var message: String?
    @State private var renaming: String?
    @State private var newName = ""
    @State private var deleting: String?
    @State private var selectedGroupID: String?

    private var activeType: String { browsingType.isEmpty ? currentType : browsingType }
    private var questionTypes: [String] { QuantityQuestionTypeRepository.types(records: records) }
    private var names: [String] {
        TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
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
            onSave: { selection = orderedSelected.joined(separator: "、"); onClose() },
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
                    TextField("搜索或新增考点", text: $search)
                        .modifier(NativeDirectionalTextFieldNavigation())
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit(addTag)
                    Button("新增", action: addTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || activeType.isEmpty || names.contains(query))
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
            selected = selection.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
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
    }

    private func toggle(_ name: String) {
        if selected.contains(name) { selected.removeAll { $0 == name } }
        else { selected.append(name) }
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
        let items = values.map {
            LibraryKnowledgePointTagItem(
                reference: LibraryKnowledgePointReference(module: activeType, name: $0),
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
                        references.map(\.name), module: activeType, groupID: groupID, subject: "数量关系",
                        records: records, context: modelContext
                    )
                    return true
                } catch {
                    message = "排序未保存"
                    return false
                }
            }
        )
    }

    private var orderedSelected: [String] {
        let orderedNames = TagLibraryRepository.tags(kind: .knowledgePoint, module: activeType, records: records)
        return orderedNames.filter { selected.contains($0) } + selected.filter { !orderedNames.contains($0) }
    }

    private func addTag() {
        guard !query.isEmpty, !activeType.isEmpty else { return }
        do {
            try TagLibraryRepository.add(
                query, kind: .knowledgePoint, module: activeType, records: records,
                context: modelContext, knowledgePointGroupID: selectedGroupID, subject: "数量关系"
            )
            if !selected.contains(query) { selected.append(query) }
            search = ""
        } catch { message = "考点保存失败，请重试" }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与其他考点重复"
            return
        }
        do {
            let result = try TagLibraryRepository.rename(old, to: value, kind: .knowledgePoint, module: activeType, subject: "数量关系", records: records, context: modelContext)
            onTagMutation?(result)
            selected = selected.map { $0 == old ? value : $0 }
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result = try TagLibraryRepository.delete(name, kind: .knowledgePoint, module: activeType, subject: "数量关系", records: records, context: modelContext)
            onTagMutation?(result)
            selected.removeAll { $0 == name }
            deleting = nil
        } catch { message = "删除失败，请重试" }
    }
}

struct VerbalReasoningKnowledgePointSelectionDialog: View {
    private static let legacyTypeSelection = "__legacy_verbal_knowledge_points__"
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
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

    private var types: [LibraryErrorType] {
        LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
            .filter { $0.module == currentModule }
    }
    private var activeTypeID: String? {
        guard !browsingTypeSelection.isEmpty, browsingTypeSelection != Self.legacyTypeSelection else { return nil }
        return browsingTypeSelection
    }
    private var activeTypeName: String {
        guard let activeTypeID else { return "旧考点" }
        return types.first(where: { $0.id == activeTypeID })?.name ?? "题型已删除"
    }
    private var names: [String] {
        guard let activeTypeID else {
            return TagLibraryRepository.tags(kind: .knowledgePoint, module: currentModule, records: records)
        }
        return VerbalReasoningKnowledgePointRepository.tags(
            module: currentModule,
            typeID: activeTypeID,
            records: records
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
        LibraryKnowledgePointGroupRepository.groups(subject: "言语理解", module: currentModule, typeID: activeTypeID, records: records)
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
                         ? "跨题型 · \(activeTypeName)"
                         : (currentTypeID.map { id in "当前题型 · \(types.first(where: { $0.id == id })?.name ?? "题型已删除")" } ?? "题型未设置"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    if showsCrossType || currentTypeID == nil || types.contains(where: { $0.id != currentTypeID }) {
                        Button(showsCrossType
                               ? (currentTypeID == nil ? "返回旧考点" : "返回当前题型")
                               : (currentTypeID == nil ? "选择题型" : "＋ 跨题型选择")) {
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
                        Text("暂无题型，请先前往设置 → 言语理解题型管理中创建。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    TextField("搜索或新增考点", text: $search)
                        .modifier(NativeDirectionalTextFieldNavigation())
                        .font(.system(size: 14))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
                        .onSubmit(addTag)
                    Button("新增", action: addTag)
                        .font(.system(size: 12, weight: .semibold))
                        .disabled(query.isEmpty || names.contains(query) || currentModule.isEmpty)
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
                                    in: selectedGroupID, allNames: names, subject: "言语理解", module: currentModule,
                                    typeID: activeTypeID, records: records
                                )
                                if groupNames.isEmpty {
                                    Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
                                } else {
                                    tagCollection(groupNames, groupID: selectedGroupID, typeID: activeTypeID)
                                }
                                let ungrouped = LibraryKnowledgePointGroupRepository.names(
                                    in: nil, allNames: names, subject: "言语理解", module: currentModule,
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
        .alert("重命名考点", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("考点名称", text: $newName).modifier(NativeDirectionalTextFieldNavigation())
            Button("保存") { renameTag() }
            Button("取消", role: .cancel) { renaming = nil }
        } message: { Text("当前题型中的该考点会同步更新。") }
        .alert("删除考点？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) { deleteTag() }
            Button("取消", role: .cancel) { deleting = nil }
        } message: { Text("将从考点库和引用该来源考点的错题中移除。") }
    }

    private func selectedTitle(for reference: LibraryKnowledgePointReference) -> String {
        if let sourceModule = reference.module, sourceModule != currentModule {
            let origin: String
            if let typeID = reference.typeID {
                origin = LibraryErrorTypeRepository.types(for: .verbalReasoning, records: records)
                    .first(where: { $0.module == sourceModule && $0.id == typeID })?.name ?? "题型已删除"
            } else {
                origin = "旧考点"
            }
            return "\(sourceModule) · \(origin) · \(reference.name)"
        }
        if reference.typeID == nil { return "旧考点 · \(reference.name)" }
        let typeName = types.first(where: { $0.id == reference.typeID })?.name ?? "题型已删除"
        guard selected.filter({ $0.name == reference.name }).count > 1 else { return "\(typeName) · \(reference.name)" }
        return "\(reference.module ?? currentModule) · \(typeName) · \(reference.name)"
    }

    private func tagCollection(_ values: [String], groupID: String?, typeID: String?) -> some View {
        let libraryNames = typeID.map {
            VerbalReasoningKnowledgePointRepository.tags(module: currentModule, typeID: $0, records: records)
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
                            records: records, context: modelContext, groupID: groupID
                        )
                    } else {
                        try TagLibraryRepository.reorderKnowledgePoints(
                            references.map(\.name), module: currentModule, groupID: groupID, subject: "言语理解",
                            records: records, context: modelContext
                        )
                    }
                    return true
                } catch {
                    message = "排序未保存"
                    return false
                }
            }
        )
    }

    @ViewBuilder
    private var legacyTagContents: some View {
        if activeTypeID == nil, !groups.isEmpty {
            let groupedNames = LibraryKnowledgePointGroupRepository.names(
                in: selectedGroupID, allNames: legacyNames, subject: "言语理解", module: currentModule,
                records: records
            )
            if groupedNames.isEmpty {
                Text("暂无考点").font(.system(size: 12)).foregroundStyle(.secondary)
            } else {
                tagCollection(groupedNames, groupID: selectedGroupID, typeID: nil)
            }
            let ungrouped = LibraryKnowledgePointGroupRepository.names(
                in: nil, allNames: legacyNames, subject: "言语理解", module: currentModule, records: records
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
                allowsReordering: false,
                onToggle: toggle,
                onReorder: { _ in false }
            )
        }
    }

    private func toggle(_ reference: LibraryKnowledgePointReference) {
        if selected.contains(reference) { selected.removeAll { $0 == reference } }
        else { selected.append(reference) }
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
        guard !query.isEmpty, !currentModule.isEmpty, !names.contains(query) else { return }
        do {
            if let activeTypeID {
                try VerbalReasoningKnowledgePointRepository.add(
                    query, module: currentModule, typeID: activeTypeID, records: records,
                    context: modelContext, groupID: selectedGroupID
                )
            } else {
                try TagLibraryRepository.add(
                    query, kind: .knowledgePoint, module: currentModule, records: records,
                    context: modelContext, knowledgePointGroupID: selectedGroupID, subject: "言语理解"
                )
            }
            toggle(LibraryKnowledgePointReference(module: currentModule, typeID: activeTypeID, name: query))
            search = ""
        } catch { message = "考点保存失败，请重试" }
    }

    private func renameTag() {
        guard let old = renaming else { return }
        let value = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != old, !names.contains(value) else {
            message = "名称不能为空或与当前题型其他考点重复"
            return
        }
        do {
            let result: LibraryTagMutationResult
            if let activeTypeID {
                result = try VerbalReasoningKnowledgePointRepository.rename(
                    old, to: value, module: currentModule, typeID: activeTypeID, records: records, context: modelContext
                )
            } else {
                result = try TagLibraryRepository.rename(
                    old, to: value, kind: .knowledgePoint, module: currentModule, subject: "言语理解", records: records, context: modelContext
                )
            }
            onTagMutation?(result)
            selected = selected.map { reference in
                reference.module == currentModule && reference.typeID == activeTypeID && reference.name == old
                    ? LibraryKnowledgePointReference(module: currentModule, typeID: activeTypeID, name: value)
                    : reference
            }
            renaming = nil
        } catch { message = "重命名失败，请重试" }
    }

    private func deleteTag() {
        guard let name = deleting else { return }
        do {
            let result: LibraryTagMutationResult
            if let activeTypeID {
                result = try VerbalReasoningKnowledgePointRepository.delete(
                    name, module: currentModule, typeID: activeTypeID, records: records, context: modelContext
                )
            } else {
                result = try TagLibraryRepository.delete(
                    name, kind: .knowledgePoint, module: currentModule, subject: "言语理解", records: records, context: modelContext
                )
            }
            onTagMutation?(result)
            selected.removeAll { $0.module == currentModule && $0.typeID == activeTypeID && $0.name == name }
            deleting = nil
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
