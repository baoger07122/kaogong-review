import SwiftUI

extension ToolbarContent {
    @ToolbarContentBuilder
    func documentToolbarBackground() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

extension View {
    /// Keeps the system navigation bar mounted on root pages so pushes only
    /// replace its title/items instead of creating and removing the whole bar.
    func stableRootNavigationBar() -> some View {
        modifier(RootPageTopLayout())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Root pages keep the custom tab bar visible while reporting visibility to
    /// the root container; pushed destinations can opt out independently.
    func rootTabBarContentInset() -> some View {
        modifier(RootTabBarRootVisibilityModifier())
    }

    /// Push destinations never own the app tab bar. Keeping this rule on the
    /// destination avoids an inherited root-level `.visible` winning during a
    /// navigation transition.
    func secondaryPageTabBarHidden() -> some View {
        modifier(RootTabBarHiddenModifier())
    }
}

private struct RootTabBarRootVisibilityModifier: ViewModifier {
    @Environment(\.rootTabContext) private var tab

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .preference(key: RootTabBarVisibilityPreferenceKey.self, value: [tab: true])
    }
}

private struct RootTabBarHiddenModifier: ViewModifier {
    @Environment(\.rootTabContext) private var tab

    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .tabBar)
            .preference(key: RootTabBarVisibilityPreferenceKey.self, value: [tab: false])
    }
}

private struct RootPageTopLayout: ViewModifier {
    @Environment(\.rootWindowTopInset) private var windowTop
    func body(content: Content) -> some View {
        // Keep the window/status inset, but let root content occupy the empty
        // transparent navigation-bar region. No assumed 44pt compensation.
        content
            .padding(.top, windowTop)
            .ignoresSafeArea(.container, edges: .top)
    }
}

struct NativeDoodleToolbarCapsule<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 2) { content }
            .padding(.horizontal, 6)
            .frame(height: 40)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule().stroke(Color.primary.opacity(0.10), lineWidth: 0.7)
            }
            .shadow(color: Color.black.opacity(0.08), radius: 5, y: 2)
    }
}

private struct NativeTagFlowMeasurement {
    let idealSize: CGSize
    let minimumWidth: CGFloat
}

/// Tags wrap at their natural width; the row itself remains a full-width tap target.
struct NativeTagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let measurements = measure(subviews)
        let width = resolvedWidth(proposal.width, measurements: measurements)
        return arrange(width: width, measurements: measurements, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let measurements = measure(subviews)
        let proposedWidth = bounds.width.isFinite ? bounds.width : proposal.width
        let width = resolvedWidth(proposedWidth, measurements: measurements)
        let result = arrange(width: width, measurements: measurements, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            let frame = result.frames[index]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func measure(_ subviews: Subviews) -> [NativeTagFlowMeasurement] {
        subviews.map { view in
            let idealSize = finiteSize(view.sizeThatFits(.unspecified))
            let zeroWidthSize = finiteSize(view.sizeThatFits(ProposedViewSize(width: 0, height: nil)))
            let usefulFallback = min(idealSize.width, max(1, idealSize.height))
            let minimumWidth = min(idealSize.width, max(zeroWidthSize.width, usefulFallback))
            return NativeTagFlowMeasurement(idealSize: idealSize, minimumWidth: minimumWidth)
        }
    }

    private func resolvedWidth(
        _ proposalWidth: CGFloat?,
        measurements: [NativeTagFlowMeasurement]
    ) -> CGFloat {
        guard !measurements.isEmpty else { return 0 }
        let naturalWidth = naturalWidth(for: measurements)
        guard naturalWidth > 0 else { return 0 }
        let minimumUsefulWidth = min(
            naturalWidth,
            max(measurements.map(\.minimumWidth).max() ?? 0, 1)
        )
        guard let proposalWidth, proposalWidth.isFinite else { return naturalWidth }
        if proposalWidth <= 0 { return minimumUsefulWidth }
        return min(naturalWidth, max(proposalWidth, minimumUsefulWidth))
    }

    private func naturalWidth(for measurements: [NativeTagFlowMeasurement]) -> CGFloat {
        var width: CGFloat = 0
        for (index, measurement) in measurements.enumerated() {
            width = finiteAdd(width, measurement.idealSize.width)
            if index > 0 { width = finiteAdd(width, finiteSpacing) }
        }
        return width
    }

    private func arrange(
        width: CGFloat,
        measurements: [NativeTagFlowMeasurement],
        subviews: Subviews
    ) -> (size: CGSize, frames: [CGRect]) {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for (index, view) in subviews.enumerated() {
            let idealSize = measurements[index].idealSize
            var size = idealSize
            if idealSize.width > width {
                size = finiteSize(view.sizeThatFits(ProposedViewSize(width: width, height: nil)))
                size.width = min(size.width, width)
            }
            if !frames.isEmpty, x >= width || size.width > width - x {
                x = 0
                y = finiteAdd(y, finiteAdd(rowHeight, finiteSpacing))
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x = finiteAdd(x, finiteAdd(size.width, finiteSpacing))
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: finiteAdd(y, rowHeight)), frames)
    }

    private var finiteSpacing: CGFloat {
        spacing.isFinite ? max(0, spacing) : 0
    }

    private func finiteSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

    private func finiteAdd(_ lhs: CGFloat, _ rhs: CGFloat) -> CGFloat {
        guard lhs.isFinite, rhs.isFinite else { return .greatestFiniteMagnitude }
        guard lhs <= CGFloat.greatestFiniteMagnitude - rhs else { return .greatestFiniteMagnitude }
        return max(0, lhs + rhs)
    }
}

struct NativeDocumentProperty: View {
    let title: String
    let value: String
    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            Text(value).font(.system(size: 12)).foregroundStyle(.primary).lineLimit(1)
            Spacer(minLength: 0)
            Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }
}
