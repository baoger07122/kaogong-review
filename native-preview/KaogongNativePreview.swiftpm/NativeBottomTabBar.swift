import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 6) {
                ForEach(RootTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .padding(7)
            .frame(maxWidth: 700)
            .glassEffect(.regular, in: Capsule())
        }
        .padding(.horizontal, 22)
        .padding(.top, 8)
        .padding(.bottom, 10)
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
            ZStack {
                if isSelected {
                    Color.clear
                        .glassEffect(.clear.interactive(), in: Capsule())
                        .glassEffectID("root-tab-selection", in: glassNamespace)
                        .glassEffectTransition(.matchedGeometry)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 22)
                    Text(tab.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
