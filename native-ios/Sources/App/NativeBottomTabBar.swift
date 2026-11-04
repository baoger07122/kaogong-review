import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionBackground

    var body: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 5) {
                tabBar
            }
            .animation(
                reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                value: selection
            )
        } else {
            tabBar
                .animation(
                    reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                    value: selection
                )
        }
    }

    private var tabBar: some View {
        HStack(spacing: 5) {
            ForEach(RootTab.availableTabs) { tab in
                tabButton(tab)
            }
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
            .background {
                if isSelected {
                    if #available(iOS 26.0, *) {
                        Capsule(style: .continuous)
                            .glassEffect(.clear.interactive(!reduceMotion), in: Capsule(style: .continuous))
                            .glassEffectID("root-tab-selection", in: selectionBackground)
                    } else {
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.075))
                            .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
