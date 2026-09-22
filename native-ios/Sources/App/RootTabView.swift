import SwiftUI

private struct RootTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RootTab> = .constant(.home)
}
private struct RootWindowTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct RootTabContextKey: EnvironmentKey {
    static let defaultValue: RootTab = .home
}
extension EnvironmentValues {
    var rootTabSelection: Binding<RootTab> {
        get { self[RootTabSelectionKey.self] }
        set { self[RootTabSelectionKey.self] = newValue }
    }
    var rootWindowTopInset: CGFloat {
        get { self[RootWindowTopInsetKey.self] }
        set { self[RootWindowTopInsetKey.self] = newValue }
    }
    var rootTabContext: RootTab {
        get { self[RootTabContextKey.self] }
        set { self[RootTabContextKey.self] = newValue }
    }
}

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
        case .home: "house"
        case .library: "square.stack.3d.up.fill"
        case .review: "checkmark.seal.fill"
        case .exams: "doc.text"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    @State private var selection: RootTab = .home
    @State private var homePath: [AppRoute] = []
    @State private var libraryPath: [LibraryRoute] = []
    @State private var settingsPath: [SettingsRoute] = []
    @StateObject private var libraryDoodleSession = LibraryDoodleSession()

    var body: some View {
        GeometryReader { window in
            TabView(selection: $selection) {
                ForEach(RootTab.allCases) { tab in
                    tabContent(tab)
                        .tabItem {
                            Label(tab.title, systemImage: tab.systemImage)
                                .accessibilityIdentifier("root-tab-\(tab.rawValue)")
                        }
                        .tag(tab)
                }
            }
            .environment(\.rootWindowTopInset, window.safeAreaInsets.top)
            .environment(\.rootTabSelection, $selection)
        }
        .tint(AppTheme.accent)
        .overlay {
            if libraryDoodleSession.isPresented {
                LibraryDoodleOverlay(session: libraryDoodleSession)
            }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: $homePath) { HomeView() }
                .toolbar(homePath.isEmpty ? .visible : .hidden, for: .tabBar)
                .environment(\.rootTabContext, .home)
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView(navigationPath: $libraryPath)
            }
                .toolbar(libraryPath.isEmpty ? .visible : .hidden, for: .tabBar)
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabContext, .library)
        case .review:
            NavigationStack { ReviewView() }
                .environment(\.rootTabContext, .review)
        case .exams:
            NavigationStack { ExamsView() }
                .environment(\.rootTabContext, .exams)
        case .settings:
            NavigationStack(path: $settingsPath) { SettingsView() }
                .toolbar(settingsPath.isEmpty ? .visible : .hidden, for: .tabBar)
                .environment(\.rootTabContext, .settings)
        }
    }
}
