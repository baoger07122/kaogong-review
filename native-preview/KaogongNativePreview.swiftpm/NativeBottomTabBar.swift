import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let itemSpacing: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            let tabs = RootTab.allCases
            let itemWidth = (
                proxy.size.width - itemSpacing * CGFloat(tabs.count - 1)
            ) / CGFloat(tabs.count)

            ZStack(alignment: .leading) {
                GlassEffectContainer(spacing: itemSpacing) {
                    Color.clear
                        .frame(width: itemWidth, height: 52)
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .offset(
                            x: selectionOffset(
                                itemWidth: itemWidth,
                                tabs: tabs
                            ),
                            y: -2
                        )
                }
                .allowsHitTesting(false)
                .zIndex(0)

                HStack(spacing: itemSpacing) {
                    ForEach(tabs) { tab in
                        tabButton(tab)
                    }
                }
                .zIndex(1)
            }
        }
        .frame(height: 52)
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(height: 0.5)
        }
        .shadow(color: .black.opacity(0.045), radius: 10, y: -3)
    }

    private func selectionOffset(
        itemWidth: CGFloat,
        tabs: [RootTab]
    ) -> CGFloat {
        guard let index = tabs.firstIndex(of: selection) else { return 0 }
        return CGFloat(index) * (itemWidth + itemSpacing)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            if reduceMotion {
                selection = tab
            } else {
                withAnimation(.spring(duration: 0.42, bounce: 0.18)) {
                    selection = tab
                }
            }
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? AppTheme.accent : Color.black)
            .transaction { transaction in
                transaction.animation = nil
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
