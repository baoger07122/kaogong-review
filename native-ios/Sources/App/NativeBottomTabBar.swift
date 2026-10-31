import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionBackground

    var body: some View {
        HStack(spacing: 5) {
            ForEach(RootTab.availableTabs) { tab in
                tabButton(tab)
            }
        }
        .padding(6)
        .frame(maxWidth: 520)
        .background(.ultraThinMaterial, in: Capsule(style: .continuous))
        .overlay {
            Capsule(style: .continuous)
                .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.75)
        }
        .shadow(color: .black.opacity(0.11), radius: 16, y: 6)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 7)
        .padding(.bottom, 7)
    }

    private func tabButton(_ tab: RootTab) -> some View {
        let isSelected = selection == tab

        return Button {
            guard selection != tab else { return }
            // The tab's navigation state changes directly. The implicit
            // animation below is scoped to the matched capsule only.
            selection = tab
        } label: {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(AppTheme.accent.opacity(0.12))
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                        .animation(
                            reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.82),
                            value: selection
                        )
                }

                VStack(spacing: 2) {
                    Image(systemName: tab.systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .frame(height: 19)
                    Text(tab.title)
                        .font(.system(size: 10, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(isSelected ? AppTheme.accent : Color.primary.opacity(0.66))
                .transaction { $0.animation = nil }
            }
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
