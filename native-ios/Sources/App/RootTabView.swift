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
        TabView(selection: $selection) {
            NavigationStack { HomeView() }
                .tabItem { Label(RootTab.home.title, systemImage: RootTab.home.systemImage) }
                .tag(RootTab.home)

            NavigationStack { LibraryView() }
                .tabItem { Label(RootTab.library.title, systemImage: RootTab.library.systemImage) }
                .tag(RootTab.library)

            NavigationStack { ReviewView() }
                .tabItem { Label(RootTab.review.title, systemImage: RootTab.review.systemImage) }
                .tag(RootTab.review)

            NavigationStack { ExamsView() }
                .tabItem { Label(RootTab.exams.title, systemImage: RootTab.exams.systemImage) }
                .tag(RootTab.exams)

            NavigationStack { SettingsView() }
                .tabItem { Label(RootTab.settings.title, systemImage: RootTab.settings.systemImage) }
                .tag(RootTab.settings)
        }
        .tint(AppTheme.accent)
        .sensoryFeedback(.selection, trigger: selection)
    }
}

