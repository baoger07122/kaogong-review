import SwiftUI

struct HomeShortcutView: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .todoStats:
            TodoStatsView()
        case .studyReport:
            StudyReportView()
        case .currentAffairs:
            CurrentAffairsView()
        case .knowledgePoints:
            KnowledgePointManagerView()
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
    private func placeholder(title: String, detail: String, image: String) -> some View {
        NativeStatusCard(title: title, detail: detail, systemImage: image, color: AppTheme.accent)
    }
}
