import SwiftUI
import QuartzCore
import UIKit

private struct RootTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RootTab> = .constant(.home)
}
private struct RootWindowTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct RootTabContextKey: EnvironmentKey {
    static let defaultValue: RootTab = .home
}

struct RootTabBarVisibilityPreferenceKey: PreferenceKey {
    static var defaultValue: [RootTab: Bool] = [:]

    static func reduce(value: inout [RootTab: Bool], nextValue: () -> [RootTab: Bool]) {
        for (tab, isVisible) in nextValue() {
            value[tab] = (value[tab] ?? true) && isVisible
        }
    }
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
    @State private var selectionGeneration = 0
    @State private var rootTabBarVisibility: [RootTab: Bool] = [:]
    @State private var homePath: [AppRoute] = []
    @State private var libraryPath: [LibraryRoute] = []
    @State private var settingsPath: [SettingsRoute] = []
    @StateObject private var libraryDoodleSession = LibraryDoodleSession()

    var body: some View {
        GeometryReader { window in
            TabView(selection: tabSelectionBinding) {
                tabPages
            }
            .toolbar(.hidden, for: .tabBar)
            .environment(\.rootWindowTopInset, window.safeAreaInsets.top)
            .environment(\.rootTabSelection, $selection)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if rootTabBarVisibility[selection] ?? true {
                    NativeBottomTabBar(selection: tabSelectionBinding)
                        .background {
                            Rectangle()
                                .fill(.ultraThinMaterial)
                                .ignoresSafeArea(edges: .bottom)
                        }
                        .accessibilityHidden(libraryDoodleSession.isPresented)
                        .allowsHitTesting(!libraryDoodleSession.isPresented)
                }
            }
            .onPreferenceChange(RootTabBarVisibilityPreferenceKey.self) { value in
                rootTabBarVisibility = value
            }
        }
        .tint(AppTheme.accent)
        .overlay {
            // Keep the fixed doodle toolbar and navigation guard above the pushed
            // page. The PencilKit surface itself is mounted by each detail page's
            // scroll content so strokes use the same coordinate system as text.
            if libraryDoodleSession.isPresented {
                LibraryDoodleOverlay(session: libraryDoodleSession)
            }
        }
        .onAppear {
            if questionBankImportRouter.pendingRequestIDs.isEmpty {
                beginTabFrameMeasurement(for: selection)
            } else {
                selectQuestionBankForIncomingFiles()
            }
        }
        .onChange(of: questionBankImportRouter.pendingRequestIDs) { _, _ in
            selectQuestionBankForIncomingFiles()
        }
    }

    private var tabPages: some View {
        ForEach(RootTab.allCases) { tab in
            tabContent(tab)
                .modifier(RootTabFirstFrameMarker(
                    tab: tab,
                    isSelected: selection == tab,
                    generation: selectionGeneration
                ))
                .tabItem {
                    Label(tab.title, systemImage: tab.systemImage)
                        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
                }
                .tag(tab)
        }
    }

    private var tabSelectionBinding: Binding<RootTab> {
        Binding(
            get: { selection },
            set: { selectTab($0) }
        )
    }

    private func selectTab(_ tab: RootTab) {
        guard selection != tab else { return }
        NativePerformanceLog.beginTabSelection(tab)
        selectionGeneration &+= 1
        selection = tab
    }

    private func beginTabFrameMeasurement(for tab: RootTab) {
        NativePerformanceLog.beginTabSelection(tab)
        selectionGeneration &+= 1
    }

    @ViewBuilder
    private func tabContent(_ tab: RootTab) -> some View {
        switch tab {
        case .home:
            NavigationStack(path: $homePath) { HomeView() }
                .toolbar(.hidden, for: .tabBar)
                .preference(key: RootTabBarVisibilityPreferenceKey.self, value: [.home: homePath.isEmpty])
                .environment(\.rootTabContext, .home)
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView(navigationPath: $libraryPath)
            }
                .toolbar(.hidden, for: .tabBar)
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabContext, .library)
        case .review:
            NavigationStack { ReviewView() }
                .toolbar(.hidden, for: .tabBar)
                .environment(\.rootTabContext, .review)
        case .questionBank:
            NavigationStack { QuestionBankView() }
                .toolbar(.hidden, for: .tabBar)
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabContext, .questionBank)
        case .settings:
            NavigationStack(path: $settingsPath) { SettingsView() }
                .toolbar(.hidden, for: .tabBar)
                .preference(key: RootTabBarVisibilityPreferenceKey.self, value: [.settings: settingsPath.isEmpty])
                .environment(\.rootTabContext, .settings)
        }
    }

    private func selectQuestionBankForIncomingFiles() {
        guard !questionBankImportRouter.pendingRequestIDs.isEmpty else { return }
        selectTab(.questionBank)
    }
}

private struct RootTabFirstFrameMarker: ViewModifier {
    let tab: RootTab
    let isSelected: Bool
    let generation: Int

    func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            RootTabFrameCommitProbe(tab: tab, isSelected: isSelected, generation: generation)
                .frame(width: 1, height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct RootTabFrameCommitProbe: UIViewRepresentable {
    let tab: RootTab
    let isSelected: Bool
    let generation: Int

    func makeUIView(context: Context) -> ProbeView {
        ProbeView(frame: .zero)
    }

    func updateUIView(_ uiView: ProbeView, context: Context) {
        uiView.markCommittedFrame(tab: tab, isSelected: isSelected, generation: generation)
    }

    final class ProbeView: UIView {
        private var lastGeneration: Int?
        private var pendingTab: RootTab?
        private var pendingGeneration: Int?
        private var displayLink: CADisplayLink?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            isAccessibilityElement = false
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                displayLink?.invalidate()
                displayLink = nil
                pendingTab = nil
                pendingGeneration = nil
            }
        }

        func markCommittedFrame(tab: RootTab, isSelected: Bool, generation: Int) {
            guard isSelected else {
                if pendingGeneration != nil {
                    displayLink?.invalidate()
                    displayLink = nil
                    pendingTab = nil
                    pendingGeneration = nil
                }
                return
            }
            guard lastGeneration != generation else { return }
            lastGeneration = generation
            pendingTab = tab
            pendingGeneration = generation
            displayLink?.invalidate()
            let displayLink = CADisplayLink(target: self, selector: #selector(displayLinkDidFire(_:)))
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }

        @objc private func displayLinkDidFire(_ link: CADisplayLink) {
            guard window != nil, let tab = pendingTab, pendingGeneration == lastGeneration else { return }
            pendingTab = nil
            pendingGeneration = nil
            displayLink?.invalidate()
            displayLink = nil
            NativePerformanceLog.markTabFirstFrame(tab)
        }
    }
}
