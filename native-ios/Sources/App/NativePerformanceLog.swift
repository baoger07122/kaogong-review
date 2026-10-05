import Foundation
import OSLog

@MainActor
enum NativePerformanceLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.baoger07122.kaogongreview.nativebeta",
        category: "native-performance"
    )
    private static var tabSelectionStarts: [String: TimeInterval] = [:]

    static func beginTabSelection(_ tab: RootTab) {
        let start = ProcessInfo.processInfo.systemUptime
        tabSelectionStarts[tab.rawValue] = start
        logger.debug("root tab selection \(tab.rawValue, privacy: .public) started")
    }

    static func markTabFirstFrame(_ tab: RootTab) {
        guard let start = tabSelectionStarts[tab.rawValue] else {
            logger.debug("root tab first frame \(tab.rawValue, privacy: .public) without selection start")
            return
        }
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        logger.debug("root tab first frame \(tab.rawValue, privacy: .public) \(formattedMilliseconds(elapsed), privacy: .public) ms")
        tabSelectionStarts[tab.rawValue] = nil
    }

    static func mark(_ label: String, since start: TimeInterval) {
        let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        logger.debug("\(label, privacy: .public) \(formattedMilliseconds(elapsed), privacy: .public) ms")
    }

    static func event(_ label: String) {
        logger.debug("\(label, privacy: .public)")
    }

    private static func formattedMilliseconds(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
