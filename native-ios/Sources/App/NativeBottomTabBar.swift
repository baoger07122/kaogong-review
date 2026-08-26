import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionBackground

    var body: some View {
        HStack {
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(RootTab.allCases) { tab in
                    tabButton(tab)
                }
            }
            .frame(maxWidth: 760)
            Spacer(minLength: 12)
        }
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().opacity(0.45)
        }
        .shadow(color: .black.opacity(0.06), radius: 12, y: -3)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            if reduceMotion {
                selection = tab
            } else {
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selection = tab
                }
            }
        } label: {
            ZStack {
                if isSelected {
                    RoundedRectangle(cornerRadius: 19, style: .continuous)
                        .fill(AppTheme.accent.gradient)
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                        .shadow(color: AppTheme.accent.opacity(0.24), radius: 8, y: 4)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .frame(height: 22)
                    Text(tab.title)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
