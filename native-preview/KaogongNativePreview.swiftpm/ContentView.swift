import SwiftUI

struct ContentView: View {
    @State private var selection: RootTab = .home

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(selection.title)
                                .font(.largeTitle.bold())
                            Text("原生导航交互预览 · 8.26.4")
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("视口宽度  \(Int(proxy.size.width)) pt")
                            .font(.caption.monospacedDigit().weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(.blue.opacity(0.1), in: Capsule())
                    }

                    HStack(spacing: 12) {
                        previewMetric("待复盘", value: "12", color: .orange)
                        previewMetric("今日完成", value: "5", color: .green)
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text("预览说明")
                            .font(.headline)
                        Text("拖动 Swift Playgrounds 的 App Preview 分隔线，观察横屏半屏宽度下的底部悬浮导航。点击五个入口，检查 iPadOS 原生 Liquid Glass 的流动切换、回弹反馈，以及图标和文字变蓝的效果。")
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

                    Spacer(minLength: 220)
                }
                .padding(24)
            }
            .background(AppTheme.groupedBackground)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomTabBar(selection: $selection)
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func previewMetric(_ title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(value)
                .font(.title.bold())
                .foregroundStyle(color)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
