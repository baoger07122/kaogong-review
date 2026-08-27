import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionTray

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RootTab.allCases) { tab in
                tabButton(tab)
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
                    Capsule(style: .continuous)
                        .fill(AppTheme.accent.opacity(0.10))
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(0.70),
                                            AppTheme.accent.opacity(0.12)
                                        ],
                                        startPoint: .top,
                                        endPoint: .bottom
                                    ),
                                    lineWidth: 0.6
                                )
                        }
                        .matchedGeometryEffect(
                            id: "root-tab-selection",
                            in: selectionTray
                        )
                        .shadow(
                            color: AppTheme.accent.opacity(0.12),
                            radius: 7,
                            y: 3
                        )
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
                .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
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
