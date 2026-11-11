import SwiftUI

struct HomeFeature: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let color: Color
    let route: AppRoute

    static let all: [HomeFeature] = [
        .init(id: "todo", title: "待办统计", systemImage: "calendar", color: Color(red: 0.29, green: 0.56, blue: 0.89), route: .todoStats),
        .init(id: "word-review", title: "词语复习", systemImage: "character.book.closed.fill", color: AppTheme.report, route: .wordReview),
        .init(id: "speed", title: "速算练习", systemImage: "number.square.fill", color: AppTheme.warning, route: .speedPractice),
        .init(id: "exams", title: "套卷记录", systemImage: "doc.text.fill", color: Color(red: 0.96, green: 0.73, blue: 0.12), route: .exams),
        .init(id: "points", title: "考点管理", systemImage: "square.grid.2x2.fill", color: AppTheme.success, route: .knowledgePoints)
    ]
}

struct HomeTodoRow: View {
    let todo: HomeTodo
    let onToggleCompleted: () -> Void
    let onEdit: () -> Void
    let onSaveNote: (String) -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    let onSkipToday: () -> Void
    let onDeleteToday: () -> Void
    let onDeleteRule: () -> Void
    let onToggleTimer: () -> Void

    @State private var noteDraft: String
    @State private var dragOffset: CGFloat = 0
    @FocusState private var noteFocused: Bool

    init(
        todo: HomeTodo,
        onToggleCompleted: @escaping () -> Void,
        onEdit: @escaping () -> Void,
        onSaveNote: @escaping (String) -> Void,
        onLongPress: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onSkipToday: @escaping () -> Void,
        onDeleteToday: @escaping () -> Void,
        onDeleteRule: @escaping () -> Void,
        onToggleTimer: @escaping () -> Void
    ) {
        self.todo = todo
        self.onToggleCompleted = onToggleCompleted
        self.onEdit = onEdit
        self.onSaveNote = onSaveNote
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onSkipToday = onSkipToday
        self.onDeleteToday = onDeleteToday
        self.onDeleteRule = onDeleteRule
        self.onToggleTimer = onToggleTimer
        _noteDraft = State(initialValue: todo.note)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Group {
                if todo.dailyRuleID != nil {
                    Menu {
                        if !todo.isCompleted {
                            Button(todo.isSkipped ? "恢复今天" : "跳过今天", action: onSkipToday)
                            Button("仅删除今天", role: .destructive, action: onDeleteToday)
                        }
                        Button("删除每日规则", role: .destructive, action: onDeleteRule)
                    } label: {
                        trailingLabel(title: "更多", systemImage: "ellipsis", color: AppTheme.accent)
                    }
                } else {
                    Button(role: .destructive, action: onDelete) {
                        trailingLabel(title: "删除", systemImage: "trash.fill", color: AppTheme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }

            rowContent
                .background(Color.white)
                .offset(x: dragOffset)
                .simultaneousGesture(swipeGesture)
        }
        .clipped()
        .onChange(of: todo.note) { _, value in
            if !noteFocused { noteDraft = value }
        }
        .onChange(of: noteFocused) { _, focused in
            if !focused && noteDraft != todo.note { onSaveNote(noteDraft) }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 10) {
            Button(action: onToggleCompleted) {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(todo.isCompleted ? AppTheme.success : Color.secondary)
            }
            .buttonStyle(.plain)

            Text(todo.subjectMark)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(AppTheme.accent)
                .frame(width: 26, height: 26)
                .background(AppTheme.accent.opacity(0.10), in: Circle())

            VStack(alignment: .leading, spacing: 3) {
                Button(action: onEdit) {
                    Text(todo.title)
                        .font(AppTheme.bodyFont)
                        .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("编辑此待办")
                TextField("添加备注", text: $noteDraft, axis: .vertical)
                    .font(AppTheme.inputFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(todo.isSkipped ? "今日已跳过" : HomeTodoSchedulePresentation.label(
                    isCompleted: todo.isCompleted,
                    completedAt: todo.completedAt,
                    scheduledAt: todo.scheduledAt
                ))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(HomeRecordRepository.durationText(
                        milliseconds: todo.elapsedMilliseconds,
                        startedAt: todo.timerStartedAt,
                        now: context.date
                    ))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundStyle(.tertiary)
                }
            }

            if !todo.isCompleted && !todo.isSkipped {
                Button(action: onToggleTimer) {
                    Image(systemName: todo.timerStartedAt == nil ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 30, height: 30)
                        .background(AppTheme.accent.opacity(0.11), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
    }

    private func trailingLabel(title: String, systemImage: String, color: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 84)
            .frame(maxHeight: .infinity)
            .background(color)
            .clipped()
    }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = min(0, max(-84, value.translation.width))
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.24, bounce: 0.05)) {
                    dragOffset = value.translation.width < -34 ? -84 : 0
                }
            }
    }
}

struct HomeDailyTodoRuleRow: View {
    let rule: HomeDailyTodoRule
    let onEdit: () -> Void
    let onTogglePause: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(rule.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(detailText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button(rule.isPaused ? "恢复" : "暂停", action: onTogglePause)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(rule.isPaused ? AppTheme.accent : .secondary)
                .accessibilityLabel(rule.isPaused ? "恢复每日待办" : "暂停每日待办")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").font(.system(size: 13))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("删除每日待办 \(rule.title)")
        }
        .padding(12)
        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
    }

    private var detailText: String {
        let state = rule.isPaused ? "已暂停 · " : ""
        let time = rule.scheduledTime.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
        return "\(state)\(rule.typeName) · 每天 \(time) · \(HomeRecordRepository.chineseDate(rule.startDate, includeYear: false))开始"
    }
}

struct HomeStickyCard: View {
    let sticky: HomeSticky
    let isInlineEditing: Bool
    @Binding var inlineText: String
    let onBeginInlineEdit: () -> Void
    let onFinishInlineEdit: () -> Void
    let onOpenEditor: () -> Void
    let onDelete: () -> Void

    @State private var dragOffset: CGFloat = 0

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Text("删除")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: visibleRevealWidth)
                    .frame(maxHeight: .infinity)
                    .background(visibleRevealWidth > 0 ? AppTheme.danger : .clear)
            }
            .buttonStyle(.plain)
            .allowsHitTesting(visibleRevealWidth > 0)

            surface
                .offset(x: dragOffset)
                .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var surface: some View {
        StickyCardSurface(sticky: sticky, isEditing: isInlineEditing) {
            if isInlineEditing {
                TextEditor(text: $inlineText)
                    .font(AppTheme.inputFont)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 66)
            } else {
                Text(StickyTextPresentation.preview(sticky.content))
                    .font(AppTheme.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } headerAccessory: {
            if isInlineEditing {
                Button(action: onFinishInlineEdit) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture {
            guard !isInlineEditing else { return }
            if StickyTextPresentation.containsRichText(sticky.content) { onOpenEditor() }
            else { onBeginInlineEdit() }
        }
        .onLongPressGesture(minimumDuration: 0.45, perform: onOpenEditor)
    }

    private var visibleRevealWidth: CGFloat { min(76, max(0, -dragOffset)) }

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 18)
            .onChanged { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                dragOffset = min(0, max(-76, value.translation.width))
            }
            .onEnded { value in
                withAnimation(.spring(duration: 0.24, bounce: 0.05)) {
                    dragOffset = value.translation.width < -34 ? -76 : 0
                }
            }
    }

}

extension Color {
    init(homeHex: String) {
        let raw = homeHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        let value = UInt64(raw, radix: 16) ?? 0xFFFFFF
        let red = Double((value >> 16) & 0xFF) / 255
        let green = Double((value >> 8) & 0xFF) / 255
        let blue = Double(value & 0xFF) / 255
        self.init(red: red, green: green, blue: blue)
    }
}
