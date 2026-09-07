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

    /// The bar belongs to this page, so it travels with the page during a pop.
    func rootTabBarContentInset() -> some View {
        modifier(PageTabBar())
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

private struct PageTabBar: ViewModifier {
    @Environment(\.rootTabSelection) private var selection
    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            NativeBottomTabBar(selection: selection)
        }
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

/// Tags wrap at their natural width; the row itself remains a full-width tap target.
struct NativeTagFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(width: proposal.width ?? 320, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(width: bounds.width, subviews: subviews)
        for (index, view) in subviews.enumerated() {
            let frame = result.frames[index]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for view in subviews {
            var size = view.sizeThatFits(.unspecified)
            if size.width > width { size = view.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
            if x > 0 && x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
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
