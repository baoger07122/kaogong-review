import SwiftUI

struct NativeBottomTabBar: View {
    static let contentHeight: CGFloat = 50

    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack {
            Spacer(minLength: 12)
            GeometryReader { geometry in
                let tabs = RootTab.allCases
                let spacing: CGFloat = 8
                let slotWidth = max(
                    0,
                    (geometry.size.width - spacing * CGFloat(max(0, tabs.count - 1)))
                        / CGFloat(max(1, tabs.count))
                )
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.055))
                        .frame(width: slotWidth, height: 44)
                        .offset(x: selectedIndicatorOffset(slotWidth: slotWidth, spacing: spacing))
                        .animation(
                            reduceMotion ? nil : .easeInOut(duration: 0.24),
                            value: selection
                        )
                        .transaction { transaction in
                            if reduceMotion { transaction.animation = nil }
                        }

                    HStack(spacing: spacing) {
                        ForEach(tabs) { tab in
                            tabButton(tab)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: 760)
            .frame(height: 44)
            Spacer(minLength: 12)
        }
        .padding(.vertical, 3)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: -3)
        .frame(height: Self.contentHeight)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
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
            .foregroundStyle(isSelected ? AppTheme.accent : Color.black)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityIdentifier("root-tab-\(tab.rawValue)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func selectedIndicatorOffset(slotWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        let selectedIndex = CGFloat(RootTab.allCases.firstIndex(of: selection) ?? 0)
        return selectedIndex * (slotWidth + spacing)
    }
}
