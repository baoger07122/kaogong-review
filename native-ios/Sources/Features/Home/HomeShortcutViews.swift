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

    @ViewBuilder
    var body: some View {
        switch route {
        case .todoStats:
            TodoStatsView()
        case .studyReport:
            StudyReportView()
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch route {
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

    private var knowledgePointCounts: [KnowledgePointSummary] {
        var result: [String: Int] = [:]
        for record in records where record.collection == "errors" || record.collection == "notes" {
            guard let value = record.jsonObject?["knowledgePoint"] as? String else { continue }
            let name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { result[name, default: 0] += 1 }
        }
        return result.map { KnowledgePointSummary(name: $0.key, count: $0.value) }.sorted { $0.count > $1.count }
    }

    private func placeholder(title: String, detail: String, image: String) -> some View {
        NativeStatusCard(title: title, detail: detail, systemImage: image, color: AppTheme.accent)
    }
}
