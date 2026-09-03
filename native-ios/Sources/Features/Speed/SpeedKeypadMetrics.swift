import Foundation

/// Mirrors src/styles/90-speed-preserved.css: four rows, 22% function column,
/// 7pt gaps, 12pt top/side padding and a two-row confirmation key.
struct SpeedKeypadMetrics {
    static let gap: CGFloat = 7
    static let sideInset: CGFloat = 12
    let width: CGFloat
    let height: CGFloat
    let bottomInset: CGFloat

    var contentWidth: CGFloat { max(0, width - Self.sideInset * 2) }
    var contentHeight: CGFloat { max(0, height - Self.sideInset - bottomInset) }
    var actionWidth: CGFloat { contentWidth * 0.22 }
    var numberWidth: CGFloat { max(0, (contentWidth - actionWidth - Self.gap * 3) / 3) }
    var rowHeight: CGFloat { max(0, (contentHeight - Self.gap * 3) / 4) }
    var confirmHeight: CGFloat { rowHeight * 2 + Self.gap }

    static func practiceSizing(contentHeight: CGFloat, viewportHeight: CGFloat, questionHeight: CGFloat = 88) -> (keyboard: CGFloat, footer: CGFloat) {
        let available = max(0, contentHeight - 52)
        // The reference page retains 64pt nav reservation + 20pt spacing below its keypad.
        // The native safe area is already outside the content; do not add it here again.
        let footer = min(84, max(0, available - 280 - max(140, questionHeight)))
        let keyboard = min(min(340, max(280, viewportHeight * 0.42)), max(0, available - footer - questionHeight))
        return (keyboard, footer)
    }
}
