import Foundation

enum QuestionBankWriteCoordinatorError: LocalizedError, Equatable {
    case busy

    var errorDescription: String? {
        "题库正在提交或整理目录，请稍后重试编辑。"
    }
}

/// A short-lived logical permit shared by question-bank imports and UI writers.
/// Acquisition never waits, so a main-thread UI edit can fail with a readable error.
enum QuestionBankWriteCoordinator {
    private final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var activeLeaseID: UUID?

        func acquire() throws -> UUID {
            lock.lock()
            defer { lock.unlock() }
            guard activeLeaseID == nil else {
                throw QuestionBankWriteCoordinatorError.busy
            }
            let id = UUID()
            activeLeaseID = id
            return id
        }

        func release(_ id: UUID) {
            lock.lock()
            if activeLeaseID == id {
                activeLeaseID = nil
            }
            lock.unlock()
        }
    }

    private static let state = State()

    final class Permit: @unchecked Sendable {
        fileprivate let id: UUID
        private let releaseLock = NSLock()
        private var isReleased = false

        fileprivate init(id: UUID) {
            self.id = id
        }

        func release() {
            releaseLock.lock()
            guard !isReleased else {
                releaseLock.unlock()
                return
            }
            isReleased = true
            releaseLock.unlock()
            QuestionBankWriteCoordinator.state.release(id)
        }

        deinit {
            release()
        }
    }

    static func acquire() throws -> Permit {
        Permit(id: try state.acquire())
    }
}
