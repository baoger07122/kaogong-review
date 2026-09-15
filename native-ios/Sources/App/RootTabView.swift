import SwiftUI
import Observation

private struct RootTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RootTab> = .constant(.home)
}
private struct RootWindowTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct RootTabContextKey: EnvironmentKey {
    static let defaultValue: RootTab = .home
}
private struct RootTabBarVisibilityKey: EnvironmentKey {
    static let defaultValue: RootTabBarVisibility? = nil
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
    var rootTabBarVisibility: RootTabBarVisibility? {
        get { self[RootTabBarVisibilityKey.self] }
        set { self[RootTabBarVisibilityKey.self] = newValue }
    }
}

@MainActor @Observable
final class RootTabBarVisibility {
    private var activePages: [RootTab: Set<UUID>] = [:]
    private var hiddenPages: [RootTab: Set<UUID>] = [:]

    func set(_ active: Bool, pageID: UUID, tab: RootTab) {
        var pages = activePages[tab] ?? []
        if active { pages.insert(pageID) } else { pages.remove(pageID) }
        activePages[tab] = pages
    }

    func isVisible(for tab: RootTab) -> Bool {
        // NavigationStack may retain a root page while an internal screen is shown.
        // A destination's explicit hide takes precedence over that root's opt-in.
        if hiddenPages[tab]?.isEmpty == false { return false }
        // Show on first mount, then let each visible page opt in explicitly.
        guard let pages = activePages[tab] else { return true }
        return !pages.isEmpty
    }

    func setHidden(_ hidden: Bool, pageID: UUID, tab: RootTab) {
        var pages = hiddenPages[tab] ?? []
        if hidden { pages.insert(pageID) } else { pages.remove(pageID) }
        hiddenPages[tab] = pages
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
    @State private var libraryPath: [LibraryRoute] = []
    @State private var tabBarVisibility = RootTabBarVisibility()
    @StateObject private var libraryDoodleSession = LibraryDoodleSession()

    var body: some View {
        GeometryReader { window in
            tabContent(selection)
                .environment(\.rootWindowTopInset, window.safeAreaInsets.top)
                .environment(\.rootTabSelection, $selection)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomTabBar(selection: $selection)
                .frame(height: tabBarVisibility.isVisible(for: selection) ? NativeBottomTabBar.contentHeight : 0, alignment: .top)
                .clipped()
                .opacity(tabBarVisibility.isVisible(for: selection) ? 1 : 0)
                .allowsHitTesting(tabBarVisibility.isVisible(for: selection))
        }
        .environment(\.rootTabBarVisibility, tabBarVisibility)
        .tint(AppTheme.accent)
        .sensoryFeedback(.selection, trigger: selection)
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
            NavigationStack { HomeView() }
                .environment(\.rootTabContext, .home)
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView(navigationPath: $libraryPath)
            }
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabContext, .library)
        case .review:
            NavigationStack { ReviewView() }
                .environment(\.rootTabContext, .review)
        case .exams:
            NavigationStack { ExamsView() }
                .environment(\.rootTabContext, .exams)
        case .settings:
            NavigationStack { SettingsView() }
                .environment(\.rootTabContext, .settings)
        }
    }
}
