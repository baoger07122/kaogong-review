import SwiftUI

private struct RootTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RootTab> = .constant(.home)
}
private struct RootWindowTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
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
    @StateObject private var libraryDoodleSession = LibraryDoodleSession()

    var body: some View {
        GeometryReader { window in
            tabContent(selection)
                .environment(\.rootWindowTopInset, window.safeAreaInsets.top)
                .environment(\.rootTabSelection, $selection)
        }
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
        case .library:
            NavigationStack { LibraryView() }
                .environmentObject(libraryDoodleSession)
        case .review:
            NavigationStack { ReviewView() }
        case .exams:
            NavigationStack { ExamsView() }
        case .settings:
            NavigationStack { SettingsView() }
        }
    }
}
