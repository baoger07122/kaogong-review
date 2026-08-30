import SwiftData
import SwiftUI

private enum TodoStatsMode: String, CaseIterable, Identifiable {
    case week = "周"
    case month = "月"
    var id: String { rawValue }
}

private struct TodoCalendarDay: Identifiable {
    let date: Date?
    var id: String { date.map(HomeRecordRepository.dayKey) ?? UUID().uuidString }
}

struct TodoStatsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var mode: TodoStatsMode = .month
    @State private var month = Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: .now)) ?? .now
    @State private var weekStart = TodoStatsView.startOfWeek(.now)
    @State private var selectedDate: Date?
    @State private var draftTitle = ""
    @State private var draftType = "yanyu"

    private var todos: [HomeTodo] { HomeRecordRepository.todos(from: records) }
    private var completed: [HomeTodo] { todos.filter(\.isCompleted) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("统计范围", selection: $mode) {
                    ForEach(TodoStatsMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
                .frame(maxWidth: .infinity)

                HStack {
                    Button { move(-1) } label: { Label(mode == .week ? "上周" : "上月", systemImage: "chevron.left") }
                    Spacer()
                    Text(periodTitle).font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { move(1) } label: { Label(mode == .week ? "下周" : "下月", systemImage: "chevron.right").labelStyle(.titleAndIcon) }
                }
                .font(AppTheme.bodyFont)

                calendar

                HStack(spacing: 10) {
                    summary(value: completedInVisibleRange.count, title: "本期完成", color: AppTheme.success)
                    summary(value: totalMinutes, title: "学习分钟", color: AppTheme.accent)
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("待办统计")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if selectedDate != nil { addDialog }
        }
    }

    private var calendar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(["一", "二", "三", "四", "五", "六", "日"], id: \.self) { value in
                    Text(value)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            let rows = calendarRows
            ForEach(rows.indices, id: \.self) { row in
                HStack(alignment: .top, spacing: 5) {
                    ForEach(rows[row]) { day in
                        dayCell(day.date)
                    }
                }
            }
        }
        .padding(12)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    @ViewBuilder
    private func dayCell(_ date: Date?) -> some View {
        if let date {
            let items = completed(on: date)
            Button {
                selectedDate = date
                draftTitle = ""
                draftType = "yanyu"
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.system(size: 12, weight: Calendar.current.isDateInToday(date) ? .bold : .medium))
                        .foregroundStyle(Calendar.current.isDateInToday(date) ? AppTheme.accent : Color.primary)
                    ForEach(items.prefix(mode == .week ? 5 : 3)) { todo in
                        Text(todo.title)
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .foregroundStyle(subjectColor(todo.type))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(subjectColor(todo.type).opacity(0.10), in: RoundedRectangle(cornerRadius: 4))
                    }
                    if items.count > (mode == .week ? 5 : 3) {
                        Text("+\(items.count - (mode == .week ? 5 : 3))")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(6)
                .frame(maxWidth: .infinity, minHeight: mode == .week ? 112 : 76, alignment: .topLeading)
                .background(Calendar.current.isDateInToday(date) ? AppTheme.accent.opacity(0.07) : Color.white, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)
        } else {
            Color.clear.frame(maxWidth: .infinity, minHeight: mode == .week ? 112 : 76)
        }
    }

    private var addDialog: some View {
        NativeEditorDialog(
            title: selectedDate.map { "\(HomeRecordRepository.chineseDate($0, includeYear: false))新建待办" } ?? "新建待办",
            canSave: !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: { selectedDate = nil },
            onSave: saveTodo
        ) {
            TextField("待办内容", text: $draftTitle, axis: .vertical)
                .textFieldStyle(NativeTextFieldStyle())
            VStack(alignment: .leading, spacing: 8) {
                NativeFieldLabel(title: "科目")
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: 7)], spacing: 7) {
                    ForEach(HomeRecordRepository.todoTypes) { type in
                        Button(type.title) { draftType = type.key }
                            .font(AppTheme.inputFont.weight(draftType == type.key ? .semibold : .regular))
                            .foregroundStyle(draftType == type.key ? AppTheme.accent : Color.primary)
                            .frame(height: 34)
                            .frame(maxWidth: .infinity)
                            .background(draftType == type.key ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045), in: Capsule())
                            .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var calendarRows: [[TodoCalendarDay]] {
        let dates: [Date?]
        if mode == .week {
            dates = (0..<14).map { Calendar.current.date(byAdding: .day, value: $0, to: weekStart) }
        } else {
            let range = Calendar.current.range(of: .day, in: .month, for: month) ?? 1..<2
            let weekday = Calendar.current.component(.weekday, from: month)
            let mondayOffset = (weekday + 5) % 7
            dates = Array(repeating: nil, count: mondayOffset) + range.compactMap {
                Calendar.current.date(byAdding: .day, value: $0 - 1, to: month)
            }.map(Optional.some)
        }
        let padded = dates + Array(repeating: nil, count: (7 - dates.count % 7) % 7)
        return stride(from: 0, to: padded.count, by: 7).map { index in
            padded[index..<min(index + 7, padded.count)].map(TodoCalendarDay.init)
        }
    }

    private var periodTitle: String {
        if mode == .month {
            return month.formatted(.dateTime.year().month(.wide).locale(Locale(identifier: "zh_CN")))
        }
        let end = Calendar.current.date(byAdding: .day, value: 13, to: weekStart) ?? weekStart
        return "\(HomeRecordRepository.chineseDate(weekStart, includeYear: false))—\(HomeRecordRepository.chineseDate(end, includeYear: false))"
    }

    private var visibleInterval: DateInterval {
        if mode == .week {
            return DateInterval(start: weekStart, end: Calendar.current.date(byAdding: .day, value: 14, to: weekStart) ?? weekStart)
        }
        return Calendar.current.dateInterval(of: .month, for: month) ?? DateInterval(start: month, duration: 0)
    }

    private var completedInVisibleRange: [HomeTodo] {
        completed.filter { todo in todo.completedAt.map(visibleInterval.contains) ?? false }
    }

    private var totalMinutes: Int {
        Int(completedInVisibleRange.reduce(0) { $0 + $1.elapsedMilliseconds } / 60_000)
    }

    private func completed(on date: Date) -> [HomeTodo] {
        completed.filter { todo in todo.completedAt.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false }
    }

    private func move(_ direction: Int) {
        if mode == .week {
            weekStart = Calendar.current.date(byAdding: .day, value: direction * 7, to: weekStart) ?? weekStart
        } else {
            month = Calendar.current.date(byAdding: .month, value: direction, to: month) ?? month
        }
    }

    private func saveTodo() {
        guard let date = selectedDate else { return }
        let todo = HomeRecordRepository.makeTodo(title: draftTitle.trimmingCharacters(in: .whitespacesAndNewlines), note: "", type: draftType, scheduledAt: date)
        try? HomeRecordRepository.save(todo: todo, records: records, context: modelContext)
        selectedDate = nil
    }

    private func summary(value: Int, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
            Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private func subjectColor(_ type: String) -> Color {
        switch type {
        case "ziliao": .green
        case "panduan": .purple
        case "shuliang": .orange
        case "changshi": Color(red: 0.42, green: 0.56, blue: 0.68)
        case "zhengzhi": .red
        case "shenlun": .mint
        default: .blue
        }
    }

    private static func startOfWeek(_ date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        return calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? Calendar.current.startOfDay(for: date)
    }
}
