import SwiftUI

struct ContentView: View {
    @State private var selection: RootTab = .home

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack { previewPage(.home) }
                .tabItem { Label(RootTab.home.title, systemImage: RootTab.home.systemImage) }
                .tag(RootTab.home)

            NavigationStack { previewPage(.library) }
                .tabItem { Label(RootTab.library.title, systemImage: RootTab.library.systemImage) }
                .tag(RootTab.library)

            NavigationStack { previewPage(.review) }
                .tabItem { Label(RootTab.review.title, systemImage: RootTab.review.systemImage) }
                .tag(RootTab.review)

            NavigationStack { previewPage(.exams) }
                .tabItem { Label(RootTab.exams.title, systemImage: RootTab.exams.systemImage) }
                .tag(RootTab.exams)

            NavigationStack { previewPage(.settings) }
                .tabItem { Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage) }
                .tag(RootTab.settings)
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
                            Text("最初版本系统 TabView 对照预览")
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
                        Text("这里使用与第一个原生 IPA 相同的系统 TabView，没有自定义导航、动画或玻璃效果。请观察 iPad 横屏和半屏时系统把导航放在顶部还是底部，并与当时安装的 IPA 对比切换手感。")
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
