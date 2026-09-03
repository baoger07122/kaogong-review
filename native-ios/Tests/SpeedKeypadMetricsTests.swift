import Foundation

@main
struct SpeedKeypadMetricsTests {
    static func close(_ a: CGFloat, _ b: CGFloat) {
        precondition(abs(a - b) < 0.001, "Geometry mismatch: \(a) != \(b)")
    }

    static func main() {
        var cases = 0
        for width: CGFloat in [320, 375, 507, 570, 590, 744, 1024, 1366] {
            for height: CGFloat in [280, 300, 340] {
                for bottom: CGFloat in [0, 20, 34] {
                    let m = SpeedKeypadMetrics(width: width, height: height, bottomInset: bottom)
                    close(3 * m.numberWidth + m.actionWidth + 3 * SpeedKeypadMetrics.gap, m.contentWidth)
                    close(4 * m.rowHeight + 3 * SpeedKeypadMetrics.gap, m.contentHeight)
                    close(2 * m.rowHeight + m.confirmHeight + 2 * SpeedKeypadMetrics.gap, m.contentHeight)
                    close(m.confirmHeight, 2 * m.rowHeight + SpeedKeypadMetrics.gap)
                    close(m.actionWidth / m.contentWidth, 0.22)
                    precondition(m.rowHeight >= 44 && m.numberWidth >= 44)
                    cases += 1
                }
            }
        }
        for content: CGFloat in [384, 420, 600, 724, 940] {
            let sizing = SpeedKeypadMetrics.practiceSizing(contentHeight: content, viewportHeight: content + 96)
            precondition(sizing.keyboard + sizing.footer + 52 + 88 <= content + 0.001)
            precondition(sizing.keyboard <= 340 && sizing.footer <= 84)
            let m = SpeedKeypadMetrics(width: 570, height: sizing.keyboard, bottomInset: 34)
            precondition(m.rowHeight >= 44)
            cases += 1
        }
        print("PASS \(cases) keypad geometry cases: row alignment, two-row confirm, 22% column, full-width fit and compact-height bounds")
    }
}
