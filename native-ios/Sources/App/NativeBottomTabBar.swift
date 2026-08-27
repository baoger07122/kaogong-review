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
        .padding(.vertical, 3)
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
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.055))
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                }

                VStack(spacing: 2) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 19)
                    Text(tab.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? AppTheme.accent : Color.black)
                .transaction { transaction in
                    transaction.animation = nil
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
