import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home
    case library
    case review
    case exams
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .library: "学习库"
        case .review: "复习"
        case .exams: "套卷"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "checklist"
        case .library: "books.vertical"
        case .review: "arrow.clockwise"
        case .exams: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    @State private var selection: RootTab = .home

    var body: some View {
        ZStack {
            ForEach(RootTab.allCases) { tab in
                tabContent(tab)
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

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack { HomeView() }
        case .library:
            NavigationStack { LibraryView() }
        case .review:
            NavigationStack { ReviewView() }
        case .exams:
            NavigationStack { ExamsView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}
