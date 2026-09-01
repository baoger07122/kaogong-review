import Foundation
import SwiftData
import SwiftUI

struct LibraryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var scope = LibraryScope()
    @State private var expandedSubject: String?
    @State private var kind: LibraryContentKind = .errors
    @State private var searchText = ""
    @State private var selectedStatus = ""
    @State private var selectedTag = ""
    @State private var cardSize: LibraryCardSize = .medium
    @State private var editorTarget: LibraryEditorTarget?
    @State private var showNewNoteType = false
    @State private var noteTypeDraft = ""
    @State private var noteTypeColor = NoteTypeRepository.colors[0]
    @State private var deleteTarget: LibraryDeleteTarget?
    @State private var inlineErrorID: String?
    @State private var wordCategory: WordCategory = .idiomDefinition
    @State private var wordSentiment = ""

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                LibrarySidebar(
                    records: records,
                    scope: $scope,
                    expandedSubject: $expandedSubject,
                    onScopeChanged: resetContextFilters
                )
                .frame(width: sidebarWidth(in: proxy.size.width))

                Divider()
                content
            }
        }
        .background(AppTheme.groupedBackground)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editorTarget) { target in
            NavigationStack {
                LibraryRecordEditorView(
                    kind: target.kind,
                    scope: scope,
                    record: records.first { $0.collection == target.kind.collection && $0.recordID == target.recordID },
                    preferredType: target.recordID == nil ? (target.kind == .words ? wordCategory.rawValue : selectedTag) : ""
                )
            }
        }
        .overlay {
            if showNewNoteType {
                noteTypeDialog
            } else if let deleteTarget {
                NativeDeleteDialog(
                    title: "删除便签",
                    message: "删除后无法在 App 内恢复。",
                    onDelete: { remove(deleteTarget); self.deleteTarget = nil },
                    onCancel: { self.deleteTarget = nil }
                )
            }
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterBar
                    if kind == .words { wordCategoryBar }
                    if kind == .notes, noteContext != nil { noteTypeBar }
                    if kind == .stickies, stickyContext != nil { stickyTagBar }
                    if let inlineErrorRecord {
                        InlineErrorEditor(
                            record: inlineErrorRecord,
                            scope: scope,
                            records: records,
                            onClose: { inlineErrorID = nil },
                            onFullEdit: {
                                editorTarget = LibraryEditorTarget(kind: .errors, recordID: inlineErrorRecord.recordID)
                                inlineErrorID = nil
                            }
                        )
                    }
                    if displayedRecords.isEmpty {
                        VStack(spacing: 10) {
                            NativeStatusCard(
                                title: emptyTitle,
                                detail: emptyDetail,
                                systemImage: emptyIcon,
                                color: .secondary
                            )
                            if kind == .words {
                                Button(action: importWordSamples) {
                                    Label("导入当前分类示例", systemImage: "square.and.arrow.down")
                                }
                                .buttonStyle(NativeSecondaryButtonStyle())
                            }
                        }
                    } else if kind == .errors, scope.subject == "判断推理", scope.module == "图形推理" {
                        GraphReasoningFlashcardView(
                            records: displayedRecords,
                            onEdit: { editorTarget = LibraryEditorTarget(kind: kind, recordID: $0.record.recordID) }
                        )
                    } else {
                        LibraryMasonryGrid(
                            records: displayedRecords,
                            kind: kind,
                            columnCount: cardSize.columnCount,
                            onOpen: { open($0) },
                            onDelete: { deleteTarget = LibraryDeleteTarget(kind: kind, recordID: $0.record.recordID) },
                            hiddenTags: kind == .notes && !selectedTag.isEmpty ? [selectedTag] : []
                        )
                    }
                }
                .padding(14)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.title)
                        .font(AppTheme.pageTitleFont)
                    Text(contextSummary)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    editorTarget = LibraryEditorTarget(kind: kind, recordID: nil)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 34, height: 34)
                        .background(AppTheme.accent.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
                .disabled((kind == .stickies && !scope.hasModuleContext) || (kind == .words && !scope.isLogicFill))
            }

            HStack(spacing: 4) {
                ForEach(availableKinds) { value in
                    Button {
                        withAnimation(.easeInOut(duration: 0.16)) { kind = value }
                        selectedStatus = ""
                        selectedTag = ""
                    } label: {
                        Text(value.rawValue)
                            .font(.system(size: 12, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(kind == value ? AppTheme.accent : Color.primary)
                            .background(kind == value ? AppTheme.secondaryBackground : Color.clear, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Color.primary.opacity(0.05), in: Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
        .background(AppTheme.groupedBackground)
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(searchPrompt, text: $searchText)
                    .font(AppTheme.inputFont)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            if kind == .errors {
                Menu {
                    Button("全部状态") { selectedStatus = "" }
                    Button("未掌握") { selectedStatus = "未掌握" }
                    Button("已掌握") { selectedStatus = "已掌握" }
                } label: {
                    filterLabel(selectedStatus.isEmpty ? "状态" : selectedStatus)
                }
            }

            if kind == .words {
                Menu {
                    Button("全部感情色彩") { wordSentiment = "" }
                    ForEach(["褒义", "贬义", "中性"], id: \.self) { value in
                        Button(value) { wordSentiment = value }
                    }
                } label: {
                    filterLabel(wordSentiment.isEmpty ? "感情色彩" : wordSentiment)
                }
            }

            if !availableTags.isEmpty && kind != .notes && kind != .words {
                Menu {
                    Button(kind == .notes ? "全部标签" : "全部分类") { selectedTag = "" }
                    ForEach(availableTags, id: \.self) { tag in
                        Button(tag) { selectedTag = tag }
                    }
                } label: {
                    filterLabel(selectedTag.isEmpty ? (kind == .notes ? "标签" : "分类") : selectedTag)
                }
            }

            HStack(spacing: 1) {
                ForEach(LibraryCardSize.allCases) { size in
                    Button(size.rawValue) { cardSize = size }
                        .font(AppTheme.auxiliaryFont.weight(cardSize == size ? .semibold : .regular))
                        .foregroundStyle(cardSize == size ? AppTheme.accent : Color.secondary)
                        .frame(width: 27, height: 28)
                        .background(cardSize == size ? AppTheme.accent.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
                        .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func filterLabel(_ value: String) -> some View {
        HStack(spacing: 4) {
            Text(value).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(AppTheme.auxiliaryFont)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .frame(height: 36)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var availableKinds: [LibraryContentKind] {
        var values: [LibraryContentKind] = [.errors, .notes]
        if scope.isLogicFill && (kind == .notes || kind == .words) { values.append(.words) }
        values.append(.stickies)
        return values
    }

    private var scopedRecords: [StoredRecord] {
        records.filter { record in
            guard record.collection == kind.collection, scope.contains(record) else { return false }
            if kind == .stickies && !scope.hasModuleContext { return false }
            if kind == .words && !scope.isLogicFill { return false }
            return true
        }
    }

    private var snapshots: [LibraryRecordSnapshot] {
        scopedRecords.map(LibraryRecordSnapshot.init)
    }

    private var displayedRecords: [LibraryRecordSnapshot] {
        let keyword = normalizedSearch(searchText)
        return snapshots.filter { snapshot in
            let matchesSearch = keyword.isEmpty || normalizedSearch(searchableText(for: snapshot.record)).contains(keyword)
            let matchesStatus = selectedStatus.isEmpty || snapshot.status == selectedStatus
            let matchesTag = selectedTag.isEmpty || snapshot.tags.contains(selectedTag)
            let object = snapshot.record.jsonObject ?? [:]
            let recordCategory = (object["category"] as? String) ?? (object["type"] as? String) ?? WordCategory.idiomDefinition.rawValue
            let matchesWordCategory = kind != .words || recordCategory == wordCategory.rawValue
            let matchesWordSentiment = kind != .words || wordSentiment.isEmpty || (object["sentiment"] as? String) == wordSentiment
            return matchesSearch && matchesStatus && matchesTag && matchesWordCategory && matchesWordSentiment
        }
        .sorted { left, right in
            if kind == .stickies, left.isPinned != right.isPinned { return left.isPinned }
            if kind == .stickies { return (left.createdAt ?? .distantPast) > (right.createdAt ?? .distantPast) }
            return (left.record.updatedAt ?? left.createdAt ?? .distantPast) > (right.record.updatedAt ?? right.createdAt ?? .distantPast)
        }
    }

    private func searchableText(for record: StoredRecord) -> String {
        let object = record.jsonObject ?? [:]
        let snapshot = LibraryRecordSnapshot(record: record)
        var values = [snapshot.title, snapshot.summary]
        if kind == .words {
            values.append(contentsOf: ["pinyin", "meaning", "example", "compareNote", "myUnderstanding", "collocations", "pos"]
                .compactMap { object[$0] as? String })
            if let terms = object["compareWords"] as? [[String: Any]] {
                values.append(contentsOf: terms.flatMap {
                    [$0["name"] as? String, $0["meaning"] as? String].compactMap { $0 }
                })
            }
        } else {
            values.append(contentsOf: snapshot.tags)
        }
        return values.joined(separator: "\n")
    }

    private func normalizedSearch(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "zh_CN"))
    }

    private var wordCategoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(WordCategory.allCases) { category in
                    Button {
                        wordCategory = category
                        wordSentiment = ""
                    } label: {
                        Label(category.shortTitle, systemImage: category.systemImage)
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                            .foregroundStyle(wordCategory == category ? AppTheme.accent : Color.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 31)
                            .background(
                                wordCategory == category ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                in: Capsule()
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var availableTags: [String] {
        if kind == .notes, let context = noteContext {
            return NoteTypeRepository.types(subject: context.subject, module: context.module, records: records).map(\.name)
        }
        if kind == .stickies, let context = stickyContext {
            return StickyTagRepository.tags(subject: context.subject, module: context.module, records: records).map(\.name)
        }
        return Array(Set(snapshots.flatMap(\.tags))).sorted()
    }

    private var inlineErrorRecord: StoredRecord? {
        guard kind == .errors, let inlineErrorID else { return nil }
        return records.first { $0.collection == "errors" && $0.recordID == inlineErrorID }
    }

    private var noteContext: (subject: String, module: String)? {
        guard let subject = scope.subject, scope.hasModuleContext else { return nil }
        return (subject, subject == "资料分析" ? "" : (scope.module ?? ""))
    }

    private var stickyContext: (subject: String, module: String)? {
        guard let subject = scope.subject, scope.hasModuleContext else { return nil }
        return (subject, subject == "资料分析" ? "" : (scope.module ?? ""))
    }

    private var noteTypeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                noteTypeChip(title: "全部", color: "#0066CC", selected: selectedTag.isEmpty) { selectedTag = "" }
                ForEach(availableNoteTypes) { item in
                    noteTypeChip(title: item.name, color: item.color, selected: selectedTag == item.name) { selectedTag = item.name }
                }
                Button {
                    noteTypeDraft = ""
                    noteTypeColor = NoteTypeRepository.colors[0]
                    showNewNoteType = true
                } label: {
                    Image(systemName: "plus").font(.system(size: 11, weight: .bold)).frame(width: 29, height: 29)
                        .background(Color.primary.opacity(0.055), in: Circle())
                }.buttonStyle(.plain)
            }
        }
    }

    private var availableNoteTypes: [NoteTypeDefinition] {
        guard let context = noteContext else { return [] }
        return NoteTypeRepository.types(subject: context.subject, module: context.module, records: records)
    }

    private var stickyTagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                noteTypeChip(title: "全部", color: "#0066CC", selected: selectedTag.isEmpty) { selectedTag = "" }
                ForEach(availableStickyTags) { item in
                    noteTypeChip(title: item.name, color: item.color, selected: selectedTag == item.name) { selectedTag = item.name }
                }
            }
        }
    }

    private var availableStickyTags: [StickyTagDefinition] {
        guard let context = stickyContext else { return [] }
        return StickyTagRepository.tags(subject: context.subject, module: context.module, records: records)
    }

    private func noteTypeChip(title: String, color: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(AppTheme.auxiliaryFont.weight(.semibold))
                .foregroundStyle(selected ? Color(homeHex: color) : .secondary)
                .padding(.horizontal, 10).frame(height: 29)
                .background(selected ? Color(homeHex: color).opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
        }.buttonStyle(.plain)
    }

    private var noteTypeDialog: some View {
        NativeEditorDialog(
            title: "新增笔记标签",
            canSave: !noteTypeDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { showNewNoteType = false },
            onSave: saveNoteType
        ) {
            TextField("标签名称", text: $noteTypeDraft).textFieldStyle(NativeTextFieldStyle())
            HStack(spacing: 12) {
                ForEach(NoteTypeRepository.colors, id: \.self) { color in
                    Button { noteTypeColor = color } label: {
                        Circle().fill(Color(homeHex: color)).frame(width: 27, height: 27)
                            .overlay(Circle().stroke(noteTypeColor == color ? Color.primary : .clear, lineWidth: 2))
                    }.buttonStyle(.plain)
                }
            }
        }
    }

    private func saveNoteType() {
        guard let context = noteContext else { return }
        let name = noteTypeDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        try? NoteTypeRepository.add(name, color: noteTypeColor, subject: context.subject, module: context.module, records: records, context: modelContext)
        selectedTag = name
        showNewNoteType = false
    }

    private var contextSummary: String {
        let values: [(String, LibraryContentKind)] = [("错题", .errors), ("笔记", .notes), ("便签", .stickies)]
        return values.map { label, value in
            let count = records.lazy.filter { $0.collection == value.collection && scope.contains($0) }.count
            return "\(count) \(label)"
        }.joined(separator: " · ")
    }

    private var emptyTitle: String {
        if kind == .stickies && !scope.hasModuleContext { return "先选择一个模块" }
        return kind.emptyTitle
    }

    private var emptyDetail: String {
        if kind == .stickies && !scope.hasModuleContext { return "每个模块的便签相互独立" }
        return kind.emptyDetail
    }

    private var emptyIcon: String {
        switch kind {
        case .errors: "checklist"
        case .notes: "note.text"
        case .stickies: "note"
        case .words: "character.book.closed"
        }
    }

    private var searchPrompt: String {
        switch kind {
        case .errors: "搜索错题 / 知识点"
        case .notes: "搜索笔记标题 / 内容"
        case .stickies: "搜索便签内容"
        case .words: "搜索词语 / 释义"
        }
    }

    private func resetContextFilters() {
        searchText = ""
        selectedStatus = ""
        selectedTag = ""
        wordSentiment = ""
        inlineErrorID = nil
        if kind == .words && !scope.isLogicFill { kind = .notes }
    }

    private func sidebarWidth(in width: CGFloat) -> CGFloat {
        min(184, max(148, width * 0.27))
    }

    private func remove(_ target: LibraryDeleteTarget) {
        try? LibraryRecordRepository.remove(kind: target.kind, id: target.recordID, records: records, context: modelContext)
    }

    private func open(_ snapshot: LibraryRecordSnapshot) {
        if kind == .errors {
            withAnimation(.easeInOut(duration: 0.18)) { inlineErrorID = snapshot.record.recordID }
        } else {
            editorTarget = LibraryEditorTarget(kind: kind, recordID: snapshot.record.recordID)
        }
    }

    private func importWordSamples() {
        guard kind == .words, scope.isLogicFill else { return }
        let now = Date.now
        for sample in WordSampleData.samples(for: wordCategory) {
            var object = sample
            let id = "word-native-\(UUID().uuidString.lowercased())"
            object["id"] = id
            object["category"] = wordCategory.rawValue
            object["type"] = wordCategory.rawValue
            object["subject"] = "言语理解"
            object["module"] = "逻辑填空"
            object["createdAt"] = ISO8601DateFormatter().string(from: now)
            object["updatedAt"] = ISO8601DateFormatter().string(from: now)
            guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { continue }
            modelContext.insert(StoredRecord(
                collection: "words",
                recordID: id,
                payload: payload,
                subject: "言语理解",
                module: "逻辑填空",
                createdAt: now,
                updatedAt: now
            ))
        }
        try? modelContext.save()
    }
}

private struct LibraryEditorTarget: Identifiable {
    let kind: LibraryContentKind
    let recordID: String?
    var id: String { "\(kind.rawValue):\(recordID ?? "new")" }
}

private struct LibraryDeleteTarget: Identifiable {
    let kind: LibraryContentKind
    let recordID: String
    var id: String { "\(kind.rawValue):\(recordID)" }
}
