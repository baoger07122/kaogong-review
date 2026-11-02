import Foundation
import OSLog

enum LibraryPerformanceLog {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.baoger07122.kaogongreview.nativebeta",
        category: "library-performance"
    )
    private static let eventLock = NSLock()
    private static var lastEventAt: [String: TimeInterval] = [:]

    static func mark(_ label: String, since start: TimeInterval) {
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        let message = String(format: "%@ %.1f ms", label, elapsedMilliseconds)
        logger.info("\(message, privacy: .public)")
    }

    static func markIfSlow(_ label: String, since start: TimeInterval, thresholdMilliseconds: Double = 24) {
        let elapsedMilliseconds = (ProcessInfo.processInfo.systemUptime - start) * 1_000
        guard elapsedMilliseconds >= thresholdMilliseconds else { return }
        let message = String(format: "%@ %.1f ms", label, elapsedMilliseconds)
        event(message, throttleKey: label)
    }

    static func event(_ label: String, throttleKey: String? = nil, minimumInterval: TimeInterval = 2) {
        let key = throttleKey ?? label
        let now = ProcessInfo.processInfo.systemUptime
        eventLock.lock()
        let shouldLog = now - (lastEventAt[key] ?? -.infinity) >= minimumInterval
        if shouldLog {
            lastEventAt[key] = now
            if lastEventAt.count > 256 {
                lastEventAt = lastEventAt.filter { now - $0.value < 60 }
            }
        }
        eventLock.unlock()
        guard shouldLog else { return }
        logger.debug("\(label, privacy: .public)")
    }

    static func shortIdentifier(_ value: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(format: "%08llx", hash & 0xffff_ffff)
    }
}
