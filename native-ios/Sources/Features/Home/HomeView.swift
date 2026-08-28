import SwiftData
import SwiftUI

struct HomeView: View {
    @Query private var records: [StoredRecord]
    @State private var showWindowToolbarTest = false

    private func count(_ collection: String) -> Int {
        records.lazy.filter { $0.collection == collection }.count
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("原生正式版")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("今天继续稳稳向前")
                        .font(.largeTitle.bold())
                    Text("当前为原生重写第一阶段，已建立独立数据空间。")
                        .foregroundStyle(.secondary)
                }

                NativeSectionHeader(title: "学习概览", subtitle: "导入旧备份后显示真实数量")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 12) {
                    metric(title: "错题", value: count("errors"), image: "xmark.circle", color: .red)
                    metric(title: "笔记", value: count("notes"), image: "note.text", color: .blue)
                    metric(title: "套卷", value: count("exams"), image: "doc.text", color: .purple)
                }

                NativeSectionHeader(title: "快捷入口")
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    NavigationLink(value: AppRoute.studyStats) {
                        shortcut(title: "学习统计", subtitle: "日历与时长", image: "chart.line.uptrend.xyaxis")
                    }
                    .buttonStyle(.plain)
                    NavigationLink(value: AppRoute.speedPractice) {
                        shortcut(title: "速算练习", subtitle: "等待原生模块", image: "sum")
                    }
                    .buttonStyle(.plain)
                }

                NativeSectionHeader(title: "今日待办")
                VStack(alignment: .leading, spacing: 8) {
                    if count("todos") == 0 {
                        Label("暂无待办，可先在设置中导入 Web 备份", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("已导入 \(count("todos")) 条待办，原生编辑将在首页阶段实现。")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .nativeCard()
            }
            .padding(24)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("首页")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showWindowToolbarTest = true
                } label: {
                    Image(systemName: "rectangle.topthird.inset.filled")
                }
                .accessibilityLabel("窗口工具栏测试")
            }
        }
        .alert("窗口工具栏测试", isPresented: $showWindowToolbarTest) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("这是 iPadOS 26 顶部窗口控件适配测试按钮。")
        }
        .navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .studyStats:
                NativePlaceholderView(title: "学习统计", detail: "将在首页原生阶段实现日历、时长与任务统计。", systemImage: "chart.line.uptrend.xyaxis")
            case .speedPractice:
                NativePlaceholderView(title: "速算练习", detail: "后续使用 SwiftUI 自定义键盘完整重写。", systemImage: "sum")
            default:
                NativePlaceholderView(title: "功能建设中", detail: "该路由已冻结，等待对应原生模块实现。")
            }
        }
    }

    private func metric(title: String, value: Int, image: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: image).font(.title2).foregroundStyle(color)
            Text("\(value)").font(.title.bold())
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }

    private func shortcut(title: String, subtitle: String, image: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: image)
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(AppTheme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .nativeCard()
    }
}
