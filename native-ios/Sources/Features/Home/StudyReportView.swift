import SwiftData
import SwiftUI

private enum StudyReportPeriod: String, CaseIterable, Identifiable {
    case day = "今日"
    case week = "本周"
    case month = "本月"
    var id: String { rawValue }
}

private struct SubjectDuration: Identifiable {
    let name: String
    let milliseconds: Double
    let color: Color
    var id: String { name }
}

struct StudyReportView: View {
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "errors" || record.collection == "notes" || record.collection == "todos"
    }) private var records: [StoredRecord]
    @State private var period: StudyReportPeriod = .day

    private var todos: [HomeTodo] { HomeRecordRepository.todos(from: records) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Picker("报告周期", selection: $period) {
                    ForEach(StudyReportPeriod.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                totalCard
                subjectCard
                if period != .day {
                    activityCard
                    noteCard
                }
                todoCard
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle("学习报告")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var totalCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("\(period.rawValue)学习时长", systemImage: "clock")
                .font(AppTheme.cardTitleFont)
            Text(durationText(totalMilliseconds))
                .font(.system(size: 30, weight: .semibold))
            Text("\(completedTodos.count) 项待办完成")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var subjectCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("科目时长").font(AppTheme.cardTitleFont)
            let maximum = subjectDurations.map(\.milliseconds).max() ?? 0
            ForEach(subjectDurations) { item in
                HStack(spacing: 9) {
                    Circle().fill(item.color).frame(width: 8, height: 8)
                    Text(shortSubject(item.name))
                        .font(AppTheme.inputFont)
                        .frame(width: 48, alignment: .leading)
                    GeometryReader { proxy in
                        Capsule()
                            .fill(Color.primary.opacity(0.055))
                            .overlay(alignment: .leading) {
                                Capsule()
                                    .fill(item.color)
                                    .frame(width: maximum > 0 ? proxy.size.width * item.milliseconds / maximum : 0)
                            }
                    }
                    .frame(height: 8)
                    Text(item.milliseconds > 0 ? minuteText(item.milliseconds) : "—")
                        .font(AppTheme.inputFont.weight(.semibold))
                        .frame(width: 44, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var activityCard: some View {
        let errors = records.filter { $0.collection == "errors" }
        let newErrors = errors.filter { record in record.createdAt.map(interval.contains) ?? false }
        return VStack(alignment: .leading, spacing: 12) {
            Text("错题统计").font(AppTheme.cardTitleFont)
            HStack {
                reportMetric("本期新增", value: newErrors.count)
                reportMetric("待掌握", value: errors.filter { ($0.indexObject?["status"] as? String) == "未掌握" }.count)
                reportMetric("已掌握", value: errors.filter { ($0.indexObject?["status"] as? String) == "已掌握" }.count)
                reportMetric("总错题", value: errors.count)
            }
        }
        .padding(16)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var noteCard: some View {
        let notes = records.filter { $0.collection == "notes" && ($0.createdAt.map(interval.contains) ?? false) }
            .sorted { ($0.createdAt ?? .distantPast) > ($1.createdAt ?? .distantPast) }
        return VStack(alignment: .leading, spacing: 10) {
            Text("笔记动态").font(AppTheme.cardTitleFont)
            if notes.isEmpty {
                Text("本期暂无笔记").font(AppTheme.bodyFont).foregroundStyle(.secondary)
            } else {
                ForEach(notes.prefix(3), id: \.compoundID) { note in
                    NavigationLink { RecordJSONDetailView(record: note).nativeToolbarBackButton() } label: {
                        HStack {
                            Image(systemName: "note.text").foregroundStyle(AppTheme.accent)
                            Text(note.title).font(AppTheme.bodyFont).lineLimit(1)
                            Spacer()
                            if let date = note.createdAt {
                                Text(HomeRecordRepository.chineseDate(date, includeYear: false))
                                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var todoCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("待办明细")
                .font(AppTheme.cardTitleFont)
                .padding(.bottom, 10)
            if completedTodos.isEmpty {
                Text("本期暂无完成的待办")
                    .font(AppTheme.bodyFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                ForEach(completedTodos) { todo in
                    HStack(spacing: 9) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(AppTheme.success)
                        Text(todo.title).font(AppTheme.bodyFont).lineLimit(1)
                        Spacer()
                        Text(todo.subjectName)
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(AppTheme.accent)
                        Text(minuteText(milliseconds(inPeriodFor: todo)))
                            .font(AppTheme.inputFont.weight(.semibold))
                    }
                    .padding(.vertical, 9)
                    Divider()
                }
            }
        }
        .padding(16)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var interval: DateInterval {
        switch period {
        case .day:
            let start = Calendar.current.startOfDay(for: .now)
            return DateInterval(start: start, end: Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now)
        case .week:
            return Calendar.current.dateInterval(of: .weekOfYear, for: .now) ?? DateInterval(start: .now, duration: 0)
        case .month:
            return Calendar.current.dateInterval(of: .month, for: .now) ?? DateInterval(start: .now, duration: 0)
        }
    }

    private var completedTodos: [HomeTodo] {
        todos.filter { $0.isCompleted && ($0.completedAt.map(interval.contains) ?? false) }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    private var subjectDurations: [SubjectDuration] {
        let definitions: [(String, String, Color)] = [
            ("言语理解", "yanyu", .blue), ("数量关系", "shuliang", .orange),
            ("判断推理", "panduan", .purple), ("资料分析", "ziliao", .green),
            ("常识判断", "changshi", Color(red: 0.42, green: 0.56, blue: 0.68)), ("申论", "shenlun", .mint)
        ]
        return definitions.map { name, type, color in
            SubjectDuration(name: name, milliseconds: todos.filter { $0.type == type }.reduce(0) { $0 + milliseconds(inPeriodFor: $1) }, color: color)
        }
    }

    private var totalMilliseconds: Double { subjectDurations.reduce(0) { $0 + $1.milliseconds } }

    private func milliseconds(inPeriodFor todo: HomeTodo) -> Double {
        var total = todo.dailyTimes.reduce(0) { result, entry in
            guard let date = dayFormatter.date(from: entry.key), interval.contains(date) else { return result }
            return result + entry.value
        }
        if let startedAt = todo.timerStartedAt, interval.contains(startedAt) {
            total += max(0, Date.now.timeIntervalSince(startedAt) * 1_000)
        } else if todo.dailyTimes.isEmpty, todo.createdAt >= interval.start, todo.createdAt < interval.end {
            total += todo.elapsedMilliseconds
        }
        return total
    }

    private func reportMetric(_ title: String, value: Int) -> some View {
        VStack(spacing: 3) {
            Text("\(value)").font(.system(size: 20, weight: .semibold))
            Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func durationText(_ milliseconds: Double) -> String {
        let minutes = Int(milliseconds / 60_000)
        return minutes >= 60 ? "\(minutes / 60)小时 \(minutes % 60)分钟" : "\(minutes)分钟"
    }

    private func minuteText(_ milliseconds: Double) -> String { "\(Int(milliseconds / 60_000))分" }
    private func shortSubject(_ value: String) -> String {
        switch value {
        case "言语理解": "言语"
        case "数量关系": "数量"
        case "判断推理": "判断"
        case "资料分析": "资料"
        case "常识判断": "常识"
        default: value
        }
    }

    private let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
