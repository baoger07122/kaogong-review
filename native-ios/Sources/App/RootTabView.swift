import SwiftUI
import QuartzCore
import UIKit

private struct RootTabSelectionKey: EnvironmentKey {
    static let defaultValue: Binding<RootTab> = .constant(.home)
}
private struct RootWindowTopInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}
private struct RootTabBarVisibilityKey: EnvironmentKey {
    static let defaultValue = false
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
    var rootTabBarIsVisible: Bool {
        get { self[RootTabBarVisibilityKey.self] }
        set { self[RootTabBarVisibilityKey.self] = newValue }
    }
}

enum RootTab: String, CaseIterable, Identifiable {
    case home
    case library
    case review
    case questionBank
    case settings

    var id: String { rawValue }

    static var availableTabs: [RootTab] { allCases.filter(\.isAvailable) }

    var isAvailable: Bool { self != .questionBank }

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
    @State private var selection: RootTab = .home
    @State private var selectionGeneration = 0
    @State private var homePath: [AppRoute] = []
    @State private var libraryPath: [LibraryRoute] = []
    @State private var settingsPath: [SettingsRoute] = []
    @State private var isReviewSessionActive = false
    @StateObject private var libraryDoodleSession = LibraryDoodleSession()

    var body: some View {
        GeometryReader { window in
            TabView(selection: tabSelectionBinding) {
                tabPages
            }
            .environment(\.rootWindowTopInset, window.safeAreaInsets.top)
            .environment(\.rootTabSelection, $selection)
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
            beginTabFrameMeasurement(for: selection)
        }
    }

    private var tabPages: some View {
        ForEach(RootTab.availableTabs) { tab in
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
        guard tab.isAvailable else { return }
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
                .environment(\.rootTabBarIsVisible, homePath.isEmpty)
                .toolbar(homePath.isEmpty ? .visible : .hidden, for: .tabBar)
        case .library:
            NavigationStack(path: $libraryPath) {
                LibraryView(navigationPath: $libraryPath)
            }
                .environmentObject(libraryDoodleSession)
                .environment(\.rootTabBarIsVisible, libraryPath.isEmpty)
                .toolbar(libraryPath.isEmpty ? .visible : .hidden, for: .tabBar)
        case .review:
            NavigationStack { ReviewView(isSessionActive: $isReviewSessionActive) }
                .environment(\.rootTabBarIsVisible, !isReviewSessionActive)
                .toolbar(isReviewSessionActive ? .hidden : .visible, for: .tabBar)
        case .questionBank:
            EmptyView()
        case .settings:
            NavigationStack(path: $settingsPath) { SettingsView() }
                .environment(\.rootTabBarIsVisible, settingsPath.isEmpty)
                .toolbar(settingsPath.isEmpty ? .visible : .hidden, for: .tabBar)
        }
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
