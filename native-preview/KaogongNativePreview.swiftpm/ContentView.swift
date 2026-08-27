import SwiftUI

struct ContentView: View {
    @State private var selection: RootTab = .library

    var body: some View {
        ZStack {
            ForEach(RootTab.allCases) { tab in
                NavigationStack { previewPage(tab) }
                    .opacity(selection == tab ? 1 : 0)
                    .allowsHitTesting(selection == tab)
                    .accessibilityHidden(selection != tab)
                    .zIndex(selection == tab ? 1 : 0)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomTabBar(selection: $selection)
        }
        .tint(AppTheme.accent)
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func previewPage(_ tab: RootTab) -> some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(tab.title)
                                .font(.largeTitle.bold())
                            Text("固定底部导航 C2 预览")
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
                        Text("底栏固定贴合页面底部。切换时只有浅蓝选中托盘在五个入口之间弹性滑动，图标和文字保持稳定，不再单独缩放或闪动。")
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
