import Foundation

struct LibraryDecodedJSONPayload: @unchecked Sendable {
    let object: [String: Any]
}

struct LibraryPayloadDecodeKey: Hashable, Sendable {
    let recordID: String
    let updatedAt: Date?
    let payloadByteCount: Int
    let source: String
}

actor LibraryPayloadDecodeCoordinator {
    static let shared = LibraryPayloadDecodeCoordinator()

    private struct Flight {
        let id: UUID
        let task: Task<LibraryDecodedJSONPayload?, Never>
        var waiters: Set<UUID>
    }

    private var flights: [LibraryPayloadDecodeKey: Flight] = [:]
    private struct Completed {
        let payload: Data
        let decoded: LibraryDecodedJSONPayload
    }

    private var completed: [LibraryPayloadDecodeKey: Completed] = [:]
    private var completedOrder: [LibraryPayloadDecodeKey] = []

    func decode(
        key: LibraryPayloadDecodeKey,
        payload: Data,
        priority: TaskPriority
    ) async -> LibraryDecodedJSONPayload? {
        guard !Task.isCancelled else { return nil }
        if let cached = completed[key], cached.payload == payload {
            return cached.decoded
        }
        let waiterID = UUID()
        let flightID: UUID
        let task: Task<LibraryDecodedJSONPayload?, Never>

        if var flight = flights[key], !flight.task.isCancelled {
            flight.waiters.insert(waiterID)
            flightID = flight.id
            task = flight.task
            flights[key] = flight
        } else {
            flightID = UUID()
            task = Task.detached(priority: priority) {
                guard !Task.isCancelled,
                      let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any],
                      !Task.isCancelled else { return nil }
                return LibraryDecodedJSONPayload(object: object)
            }
            flights[key] = Flight(id: flightID, task: task, waiters: [waiterID])
        }

        let value = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            Task { await self.release(key: key, flightID: flightID, waiterID: waiterID) }
        }
        release(key: key, flightID: flightID, waiterID: waiterID)
        guard !Task.isCancelled else { return nil }
        if let value, key.source == "payload", payload.count <= 512 * 1024 {
            completedOrder.removeAll { $0 == key }
            completedOrder.append(key)
            completed[key] = Completed(payload: payload, decoded: value)
            if completedOrder.count > 4 {
                completed.removeValue(forKey: completedOrder.removeFirst())
            }
        }
        return value
    }

    private func release(key: LibraryPayloadDecodeKey, flightID: UUID, waiterID: UUID) {
        guard var flight = flights[key],
              flight.id == flightID,
              flight.waiters.remove(waiterID) != nil else { return }
        if flight.waiters.isEmpty {
            flight.task.cancel()
            flights[key] = nil
        } else {
            flights[key] = flight
        }
    }
}
