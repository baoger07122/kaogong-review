import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(RootTab.allCases) { tab in
                    tabButton(tab)
                }
            }
        }
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
                        .offset(y: -2)
                }

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
