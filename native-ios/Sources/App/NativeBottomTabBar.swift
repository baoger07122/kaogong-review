import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionBackground

    var body: some View {
        tabBar
    }

    private var tabBar: some View {
        ZStack {
            selectionIndicators

            HStack(spacing: 5) {
                ForEach(RootTab.availableTabs) { tab in
                    tabButton(tab)
                }
            }
            .zIndex(1)
        }
        .padding(6)
        .frame(maxWidth: 520)
        .background {
            if #available(iOS 26.0, *) {
                Color.clear.glassEffect(.regular, in: Capsule(style: .continuous))
            } else {
                Capsule(style: .continuous).fill(.ultraThinMaterial)
            }
        }
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.065), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.08), radius: 16, y: 6)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 7)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var selectionIndicators: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 5) {
                    HStack(spacing: 5) {
                        ForEach(RootTab.availableTabs) { tab in
                            Group {
                                if selection == tab {
                                    Capsule(style: .continuous)
                                        .fill(Color.clear)
                                        .glassEffect(.clear.interactive(), in: Capsule(style: .continuous))
                                        .glassEffectID("root-tab-selection", in: selectionBackground)
                                } else {
                                    Color.clear
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                        }
                    }
                }
            } else {
                HStack(spacing: 5) {
                    ForEach(RootTab.availableTabs) { tab in
                        Group {
                            if selection == tab {
                                Capsule(style: .continuous)
                                    .fill(Color.primary.opacity(0.075))
                                    .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                                    .animation(
                                        reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                                        value: selection
                                    )
                            } else {
                                Color.clear
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                    }
                }
            }
        }
        .frame(height: 44)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            // The tab's navigation state changes directly. The implicit
            // animation below is scoped to the matched capsule only.
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 19)
                Text(tab.title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.accent : Color.primary)
            .transaction { $0.animation = nil }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
