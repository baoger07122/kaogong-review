import SwiftUI

struct HomeFeature: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let color: Color
    let route: AppRoute

    static let all: [HomeFeature] = [
        .init(id: "todo", title: "待办统计", systemImage: "calendar", color: Color(red: 0.29, green: 0.56, blue: 0.89), route: .todoStats),
        .init(id: "report", title: "学习报告", systemImage: "chart.bar.fill", color: AppTheme.report, route: .studyReport),
        .init(id: "speed", title: "速算练习", systemImage: "number.square.fill", color: AppTheme.warning, route: .speedPractice),
        .init(id: "affairs", title: "时政常识", systemImage: "doc.text.fill", color: Color(red: 0.96, green: 0.73, blue: 0.12), route: .currentAffairs),
        .init(id: "points", title: "考点管理", systemImage: "square.grid.2x2.fill", color: AppTheme.success, route: .knowledgePoints)
    ]
}

struct HomeTodoRow: View {
    let todo: HomeTodo
    let onToggleCompleted: () -> Void
    let onSaveNote: (String) -> Void
    let onLongPress: () -> Void
    let onDelete: () -> Void
    let onToggleTimer: () -> Void

    @State private var noteDraft: String
    @State private var dragOffset: CGFloat = 0
    @FocusState private var noteFocused: Bool

    init(
        todo: HomeTodo,
        onToggleCompleted: @escaping () -> Void,
        onSaveNote: @escaping (String) -> Void,
        onLongPress: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onToggleTimer: @escaping () -> Void
    ) {
        self.todo = todo
        self.onToggleCompleted = onToggleCompleted
        self.onSaveNote = onSaveNote
        self.onLongPress = onLongPress
        self.onDelete = onDelete
        self.onToggleTimer = onToggleTimer
        _noteDraft = State(initialValue: todo.note)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button(role: .destructive, action: onDelete) {
                Label("删除", systemImage: "trash.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.danger)
            }
            .buttonStyle(.plain)

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
                Text(todo.title)
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(todo.isCompleted ? .secondary : .primary)
                    .lineLimit(2)
                TextField("添加备注", text: $noteDraft, axis: .vertical)
                    .font(AppTheme.inputFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1...2)
                    .textFieldStyle(.plain)
                    .focused($noteFocused)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(scheduleText)
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

            if !todo.isCompleted {
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

    private var scheduleText: String {
        let time = todo.scheduledAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
        if Calendar.current.isDateInToday(todo.scheduledAt) { return time }
        return "\(HomeRecordRepository.chineseDate(todo.scheduledAt, includeYear: false))\n\(time)"
    }

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
                    .frame(width: 76)
                    .frame(maxHeight: .infinity)
                    .background(AppTheme.danger)
            }
            .buttonStyle(.plain)

            surface
                .offset(x: dragOffset)
                .simultaneousGesture(swipeGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var surface: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if sticky.isPinned {
                    Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(AppTheme.warning)
                }
                Spacer()
                if isInlineEditing {
                    Button(action: onFinishInlineEdit) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }

            if isInlineEditing {
                TextEditor(text: $inlineText)
                    .font(AppTheme.inputFont)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 66)
            } else {
                Text(plainText(sticky.content))
                    .font(AppTheme.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !sticky.tag.isEmpty {
                Text(sticky.tag)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.white.opacity(0.60), in: Capsule())
            }
            HStack {
                Spacer()
                Text(HomeRecordRepository.chineseDate(sticky.createdAt, includeYear: false))
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(homeHex: sticky.colorHex), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isInlineEditing ? AppTheme.accent.opacity(0.48) : Color.primary.opacity(0.06), lineWidth: isInlineEditing ? 1.2 : 0.6)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture { if !isInlineEditing { onBeginInlineEdit() } }
        .onLongPressGesture(minimumDuration: 0.45, perform: onOpenEditor)
    }

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

    private func plainText(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
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
