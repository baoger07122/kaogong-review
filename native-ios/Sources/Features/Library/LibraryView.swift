import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query private var records: [StoredRecord]
    @State private var scope = LibraryScope()
    @State private var expandedSubject: String?
    @State private var kind: LibraryContentKind = .errors
    @State private var searchText = ""
    @State private var selectedStatus = ""
    @State private var selectedTag = ""
    @State private var cardSize: LibraryCardSize = .medium

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
    }

    private var content: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    filterBar
                    if displayedRecords.isEmpty {
                        NativeStatusCard(
                            title: emptyTitle,
                            detail: emptyDetail,
                            systemImage: emptyIcon,
                            color: .secondary
                        )
                    } else {
                        LibraryMasonryGrid(records: displayedRecords, kind: kind, columnCount: cardSize.columnCount)
                    }
                }
                .padding(14)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(scope.title)
                    .font(AppTheme.pageTitleFont)
                Text(contextSummary)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
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

            if !availableTags.isEmpty {
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
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return snapshots.filter { snapshot in
            let matchesSearch = keyword.isEmpty
                || snapshot.title.localizedCaseInsensitiveContains(keyword)
                || snapshot.summary.localizedCaseInsensitiveContains(keyword)
                || snapshot.tags.contains { $0.localizedCaseInsensitiveContains(keyword) }
            let matchesStatus = selectedStatus.isEmpty || snapshot.status == selectedStatus
            let matchesTag = selectedTag.isEmpty || snapshot.tags.contains(selectedTag)
            return matchesSearch && matchesStatus && matchesTag
        }
        .sorted { ($0.record.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.record.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    private var availableTags: [String] {
        Array(Set(snapshots.flatMap(\.tags))).sorted()
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
        if kind == .words && !scope.isLogicFill { kind = .notes }
    }

    private func sidebarWidth(in width: CGFloat) -> CGFloat {
        min(184, max(148, width * 0.27))
    }
}
