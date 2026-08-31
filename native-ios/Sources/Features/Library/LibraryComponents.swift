import SwiftUI

struct LibrarySidebar: View {
    let records: [StoredRecord]
    @Binding var scope: LibraryScope
    @Binding var expandedSubject: String?
    let onScopeChanged: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                Text("学习库")
                    .font(AppTheme.pageTitleFont)
                    .padding(.horizontal, 12)
                    .padding(.top, 16)
                    .padding(.bottom, 8)

                Button {
                    scope = LibraryScope()
                    expandedSubject = nil
                    onScopeChanged()
                } label: {
                    sidebarRow(
                        title: "全部",
                        systemImage: "tray.full.fill",
                        color: AppTheme.accent,
                        count: records.filter { ["errors", "notes", "stickies"].contains($0.collection) }.count,
                        selected: scope.isAll,
                        showsArrow: false,
                        expanded: false
                    )
                }
                .buttonStyle(.plain)

                ForEach(SubjectDefinition.all) { subject in
                    subjectSection(subject)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 24)
        }
        .background(AppTheme.secondaryBackground.opacity(0.72))
    }

    @ViewBuilder
    private func subjectSection(_ subject: SubjectDefinition) -> some View {
        let expanded = expandedSubject == subject.name
        let selected = scope.subject == subject.name && scope.module == nil

        Button {
            scope.subject = subject.name
            scope.module = nil
            if subject.isFlat {
                expandedSubject = nil
            } else {
                expandedSubject = expanded ? nil : subject.name
            }
            onScopeChanged()
        } label: {
            sidebarRow(
                title: subject.name,
                systemImage: subject.systemImage,
                color: subject.color,
                count: count(subject: subject.name),
                selected: selected,
                showsArrow: !subject.isFlat,
                expanded: expanded
            )
        }
        .buttonStyle(.plain)

        if expanded && !subject.isFlat {
            VStack(spacing: 1) {
                ForEach(subject.modules, id: \.self) { module in
                    Button {
                        scope = LibraryScope(subject: subject.name, module: module)
                        onScopeChanged()
                    } label: {
                        HStack(spacing: 8) {
                            Text(module)
                                .font(.system(size: 12, weight: scope.subject == subject.name && scope.module == module ? .semibold : .regular))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            let moduleCount = count(subject: subject.name, module: module)
                            if moduleCount > 0 {
                                Text("\(moduleCount)")
                                    .font(AppTheme.auxiliaryFont.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(scope.subject == subject.name && scope.module == module ? AppTheme.accent : Color.primary)
                        .padding(.leading, 42)
                        .padding(.trailing, 12)
                        .frame(height: 34)
                        .background(
                            scope.subject == subject.name && scope.module == module ? AppTheme.accent.opacity(0.09) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func sidebarRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        selected: Bool,
        showsArrow: Bool,
        expanded: Bool
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(selected ? AppTheme.accent : color)
                .frame(width: 22)
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Spacer(minLength: 4)
            if count > 0 {
                Text("\(count)")
                    .font(AppTheme.auxiliaryFont.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if showsArrow {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 40)
        .foregroundStyle(selected ? AppTheme.accent : Color.primary)
        .background(
            selected ? AppTheme.accent.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .contentShape(Rectangle())
    }

    private func count(subject: String, module: String? = nil) -> Int {
        records.lazy.filter {
            ["errors", "notes", "stickies"].contains($0.collection)
                && $0.subject == subject
                && (module == nil || $0.module == module)
        }.count
    }
}

struct LibraryRecordCard: View {
    let snapshot: LibraryRecordSnapshot
    let kind: LibraryContentKind
    var hiddenTags: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let firstTag = visibleTags.first {
                    Text(firstTag)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10), in: Capsule())
                } else if let status = snapshot.status, !status.isEmpty {
                    Text(status)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Spacer()
                if let date = snapshot.createdAt {
                    Text(date, format: .dateTime.month().day())
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(snapshot.title)
                .font(AppTheme.bodyFont)
                .foregroundStyle(.primary)
                .lineLimit(kind == .errors ? 5 : 3)

            if !snapshot.summary.isEmpty && snapshot.summary != snapshot.title {
                Text(snapshot.summary)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if visibleTags.count > 1 {
                Text(visibleTags.dropFirst().joined(separator: " · "))
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
        }
    }

    private var visibleTags: [String] {
        snapshot.tags.filter { !hiddenTags.contains($0) }
    }

    private var tint: Color {
        switch kind {
        case .errors: AppTheme.danger
        case .notes: AppTheme.accent
        case .stickies: .orange
        case .words: .purple
        }
    }

    private var cardBackground: Color {
        guard kind == .stickies, let value = snapshot.colorHex else { return AppTheme.secondaryBackground }
        return Color(homeHex: value).opacity(0.26)
    }
}

struct LibraryMasonryGrid: View {
    let records: [LibraryRecordSnapshot]
    let kind: LibraryContentKind
    let columnCount: Int
    let onOpen: (LibraryRecordSnapshot) -> Void
    let onDelete: (LibraryRecordSnapshot) -> Void
    var hiddenTags: Set<String> = []

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ForEach(0..<max(1, columnCount), id: \.self) { column in
                VStack(spacing: 10) {
                    ForEach(
                        Array(records.enumerated()).filter { $0.offset % max(1, columnCount) == column },
                        id: \.element.id
                    ) { _, record in
                        cardLink(record)
                    }
                }
            }
        }
    }

    private func cardLink(_ record: LibraryRecordSnapshot) -> some View {
        Group {
            if kind == .stickies {
                LibrarySwipeDeleteCard(onDelete: { onDelete(record) }) {
                    openButton(record)
                }
            } else {
                openButton(record)
            }
        }
    }

    private func openButton(_ record: LibraryRecordSnapshot) -> some View {
        Button { onOpen(record) } label: {
            LibraryRecordCard(snapshot: record, kind: kind, hiddenTags: hiddenTags)
        }
            .buttonStyle(.plain)
    }
}

private struct LibrarySwipeDeleteCard<Content: View>: View {
    let onDelete: () -> Void
    let content: Content
    @State private var offset: CGFloat = 0

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 58)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.danger, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-66, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldOpen = value.predictedEndTranslation.width < -34 || value.translation.width < -30
                            withAnimation(.spring(duration: 0.22, bounce: 0.05)) { offset = shouldOpen ? -66 : 0 }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}
