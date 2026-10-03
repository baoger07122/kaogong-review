import Foundation
import OSLog

enum LibraryPerformanceLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.baoger07122.kaogongreview.nativebeta",
        category: "library-performance"
    )

    static func mark(_ label: String, since start: TimeInterval) {
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        let message = String(format: "%@ %.1f ms", label, elapsedMilliseconds)
        logger.debug("\(message, privacy: .public)")
    }
}
