import SwiftData
import SwiftUI

private struct KnowledgePointSummary: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

struct HomeShortcutView: View {
    let route: AppRoute
    @Query private var records: [StoredRecord]

    private var todos: [HomeTodo] { HomeRecordRepository.todos(from: records) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                switch route {
                case .todoStats:
                    todoStats
                case .studyReport:
                    studyReport
                case .speedPractice:
                    placeholder(
                        title: "原生速算将在专项阶段实现",
                        detail: "入口和返回路径已经恢复；自定义键盘、题型、计时、音效与全局震动仍按第七阶段验收。",
                        image: "number.square.fill"
                    )
                case .currentAffairs:
                    currentAffairs
                case .knowledgePoints:
                    knowledgePoints
                default:
                    placeholder(title: "功能建设中", detail: "当前路由尚未进入正式重写阶段。", image: "hammer")
                }
            }
            .padding(20)
        }
        .background(Color.white)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: String {
        switch route {
        case .todoStats: "待办统计"
        case .studyReport: "学习报告"
        case .speedPractice: "速算练习"
        case .currentAffairs: "时政常识"
        case .knowledgePoints: "考点管理"
        default: "功能"
        }
    }

    private var todoStats: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                metric(value: "\(completedToday.count)", title: "今日完成", color: AppTheme.success)
                metric(value: "\(todos.filter { !$0.isCompleted }.count)", title: "待完成", color: AppTheme.warning)
            }
            section(title: "今日完成记录") {
                if completedToday.isEmpty {
                    Text("今天还没有完成记录")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(completedToday) { todo in
                        HStack {
                            Text(todo.subjectMark)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(AppTheme.accent)
                                .frame(width: 24, height: 24)
                                .background(AppTheme.accent.opacity(0.10), in: Circle())
                            Text(todo.title).lineLimit(1)
                            Spacer()
                            Text(HomeRecordRepository.durationText(milliseconds: todo.elapsedMilliseconds, startedAt: nil))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .font(AppTheme.bodyFont)
                    }
                }
            }
        }
    }

    private var studyReport: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                metric(value: durationMinutes, title: "累计学习分钟", color: AppTheme.report)
                metric(value: "\(records.filter { $0.collection == "errors" && isThisWeek($0.createdAt) }.count)", title: "本周新增错题", color: AppTheme.accent)
            }
            section(title: "知识资产") {
                reportRow("错题", value: records.filter { $0.collection == "errors" }.count)
                reportRow("笔记", value: records.filter { $0.collection == "notes" }.count)
                reportRow("便签", value: records.filter { $0.collection == "stickies" }.count)
                reportRow("套卷", value: records.filter { $0.collection == "exams" }.count)
            }
        }
    }

    private var currentAffairs: some View {
        let notes = records.filter {
            $0.collection == "notes" && ($0.subject == "常识判断" || $0.subject == "政治理论")
        }
        return VStack(alignment: .leading, spacing: 10) {
            if notes.isEmpty {
                placeholder(title: "暂无时政笔记", detail: "导入或新增常识判断、政治理论笔记后在这里集中查看。", image: "doc.text")
            } else {
                ForEach(notes, id: \.compoundID) { record in
                    NavigationLink {
                        RecordJSONDetailView(record: record)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text.fill").foregroundStyle(AppTheme.warning)
                            Text(record.title).font(AppTheme.bodyFont).lineLimit(2)
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                        }
                        .padding(14)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var knowledgePoints: some View {
        let counts = knowledgePointCounts
        return VStack(alignment: .leading, spacing: 10) {
            if counts.isEmpty {
                placeholder(title: "暂无考点", detail: "错题和笔记中的考点字段会自动汇总到这里。", image: "square.grid.2x2")
            } else {
                ForEach(counts) { item in
                    HStack {
                        Text(item.name).font(AppTheme.cardTitleFont)
                        Spacer()
                        Text("\(item.count) 条内容").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    private var completedToday: [HomeTodo] {
        todos.filter { todo in
            guard todo.isCompleted, let completedAt = todo.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
    }

    private var durationMinutes: String {
        let milliseconds = todos.reduce(0) { $0 + $1.elapsedMilliseconds }
        return "\(Int(milliseconds / 60_000))"
    }

    private var knowledgePointCounts: [KnowledgePointSummary] {
        var result: [String: Int] = [:]
        for record in records where record.collection == "errors" || record.collection == "notes" {
            guard let value = record.jsonObject?["knowledgePoint"] as? String else { continue }
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { result[name, default: 0] += 1 }
        }
        return result.map { KnowledgePointSummary(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    private func isThisWeek(_ date: Date?) -> Bool {
        guard let date, let interval = Calendar.current.dateInterval(of: .weekOfYear, for: .now) else { return false }
        return interval.contains(date)
    }

    private func metric(value: String, title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 22, weight: .semibold)).foregroundStyle(color)
            Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(AppTheme.sectionTitleFont)
            content()
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func reportRow(_ title: String, value: Int) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text("\(value)").fontWeight(.medium)
        }
        .font(AppTheme.bodyFont)
    }

    private func placeholder(title: String, detail: String, image: String) -> some View {
        NativeStatusCard(title: title, detail: detail, systemImage: image, color: AppTheme.accent)
    }
}
