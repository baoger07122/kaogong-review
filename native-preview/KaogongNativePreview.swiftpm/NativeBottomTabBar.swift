import SwiftUI

struct NativeBottomTabBar: View {
    @Binding var selection: RootTab
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionBackground

    var body: some View {
        HStack(spacing: 6) {
            ForEach(RootTab.allCases) { tab in
                tabButton(tab)
            }
        }
        .padding(7)
        .frame(maxWidth: 700)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .stroke(.white.opacity(0.62), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.08), radius: 18, y: 7)
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
                withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                    selection = tab
                }
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                        .matchedGeometryEffect(id: "root-tab-selection", in: selectionBackground)
                        .overlay {
                            Capsule(style: .continuous)
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(0.95),
                                            AppTheme.accent.opacity(0.18),
                                            .white.opacity(0.55)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                        .shadow(color: AppTheme.accent.opacity(0.08), radius: 8, y: 4)
                        .shadow(color: .white.opacity(0.7), radius: 3, y: -1)
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
