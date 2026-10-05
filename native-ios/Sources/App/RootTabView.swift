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
    case questionBank
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .library: "学习库"
        case .review: "复习"
        case .questionBank: "真题"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "square.stack.3d.up.fill"
        case .review: "checkmark.seal.fill"
        case .questionBank: "books.vertical.fill"
        case .settings: "gearshape"
        }
    }
}

struct RootTabView: View {
    @EnvironmentObject private var questionBankImportRouter: QuestionBankImportRouter
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
                        .modifier(RootTabFirstFrameMarker(tab: tab))
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
            // Keep the fixed doodle toolbar and navigation guard above the pushed
            // page. The PencilKit surface itself is mounted by each detail page's
            // scroll content so strokes use the same coordinate system as text.
            LibraryDoodleOverlay(session: libraryDoodleSession)
                .opacity(libraryDoodleSession.isPresented ? 1 : 0)
                .allowsHitTesting(libraryDoodleSession.isPresented)
                .accessibilityHidden(!libraryDoodleSession.isPresented)
        }
        .onAppear {
            NativePerformanceLog.beginTabSelection(selection)
            selectQuestionBankForIncomingFiles()
        }
        .onChange(of: selection) { _, selected in
            NativePerformanceLog.beginTabSelection(selected)
        }
        .onChange(of: questionBankImportRouter.pendingRequestIDs) { _, _ in
            selectQuestionBankForIncomingFiles()
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
                .toolbar(.visible, for: .tabBar)
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabContext, .library)
        case .review:
            NavigationStack { ReviewView() }
                .toolbar(.visible, for: .tabBar)
                .environment(\.rootTabContext, .review)
        case .questionBank:
            NavigationStack { QuestionBankView() }
                .toolbar(.visible, for: .tabBar)
                .environment(\.rootTabContext, .questionBank)
        case .settings:
            NavigationStack(path: $settingsPath) { SettingsView() }
                .toolbar(settingsPath.isEmpty ? .visible : .hidden, for: .tabBar)
                .environment(\.rootTabContext, .settings)
        }
    }

    private func selectQuestionBankForIncomingFiles() {
        guard !questionBankImportRouter.pendingRequestIDs.isEmpty else { return }
        selection = .questionBank
    }
}

private struct RootTabFirstFrameMarker: ViewModifier {
    let tab: RootTab

    func body(content: Content) -> some View {
        content.onAppear { NativePerformanceLog.markTabFirstFrame(tab) }
    }
}
