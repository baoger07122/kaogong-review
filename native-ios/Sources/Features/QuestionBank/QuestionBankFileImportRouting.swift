import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct QuestionBankFileRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
}

enum QuestionBankPickerSelectionResult: Equatable {
    case selected(QuestionBankImportSelectionCoordinator.Selection)
    case emptySelection
    case emptyURL
    case nonFileURL
    case duplicate
    case staleRequest
}

enum QuestionBankPickerDismissalResult: Equatable {
    case awaitingCallback
    case selectionAlreadyReceived
    case previewAlreadyPresented
    case alreadyAwaitingCallback
    case staleRequest
}

/// Keeps picker request identity alive across document-picker and SwiftUI
/// dismissal callbacks. Dismissal is only a hint that a callback may be late;
/// it does not invalidate the request.
@MainActor
final class QuestionBankImportSelectionCoordinator: ObservableObject {
    struct Selection: Equatable {
        let id: UUID
        let url: URL
    }

    private enum Phase {
        case idle
        case selecting
        case dismissedAwaitingCallback
        case dismissedWithoutCallback
        case selected(URL)
        case preparing
        case preview
    }

    private(set) var activePickerRequestID: UUID?
    private var phase: Phase = .idle

    var hasActivePickerRequest: Bool { activePickerRequestID != nil }

    @discardableResult
    func beginPicker() -> UUID {
        let id = UUID()
        activePickerRequestID = id
        phase = .selecting
        return id
    }

    @discardableResult
    func receivePickedURLs(requestID: UUID, urls: [URL]) -> QuestionBankPickerSelectionResult {
        guard activePickerRequestID == requestID else { return .staleRequest }
        switch phase {
        case .selecting, .dismissedAwaitingCallback, .dismissedWithoutCallback:
            break
        default:
            return .duplicate
        }

        guard let url = urls.first else {
            finishPickerRequest(requestID: requestID)
            return .emptySelection
        }
        guard !url.absoluteString.isEmpty else {
            finishPickerRequest(requestID: requestID)
            return .emptyURL
        }
        guard url.isFileURL else {
            finishPickerRequest(requestID: requestID)
            return .nonFileURL
        }
        guard !url.path.isEmpty else {
            finishPickerRequest(requestID: requestID)
            return .emptyURL
        }

        phase = .selected(url)
        return .selected(Selection(id: requestID, url: url))
    }

    func pickerWasDismissed(requestID: UUID) -> QuestionBankPickerDismissalResult {
        guard activePickerRequestID == requestID else { return .staleRequest }
        switch phase {
        case .selecting:
            phase = .dismissedAwaitingCallback
            return .awaitingCallback
        case .dismissedAwaitingCallback, .dismissedWithoutCallback:
            return .alreadyAwaitingCallback
        case .selected, .preparing:
            return .selectionAlreadyReceived
        case .preview:
            return .previewAlreadyPresented
        case .idle:
            return .staleRequest
        }
    }

    /// Called only after a short dismissal grace period. The request remains
    /// eligible for a late didPick callback until a new picker supersedes it.
    func noteDismissalWithoutCallback(requestID: UUID) -> Bool {
        guard activePickerRequestID == requestID,
              case .dismissedAwaitingCallback = phase else { return false }
        phase = .dismissedWithoutCallback
        return true
    }

    func takePendingSelection(requestID: UUID) -> Selection? {
        guard activePickerRequestID == requestID,
              case .selected(let url) = phase else { return nil }
        phase = .preparing
        return Selection(id: requestID, url: url)
    }

    func markPreviewReady(requestID: UUID) -> Bool {
        guard activePickerRequestID == requestID, case .preparing = phase else { return false }
        phase = .preview
        return true
    }

    @discardableResult
    func cancelPickerRequest(requestID: UUID) -> Bool {
        guard activePickerRequestID == requestID else { return false }
        switch phase {
        case .selecting, .dismissedAwaitingCallback, .dismissedWithoutCallback:
            clearRequest()
            return true
        default:
            return false
        }
    }

    func finishPickerRequest(requestID: UUID) {
        guard activePickerRequestID == requestID else { return }
        clearRequest()
    }

    func failPickerRequest(requestID: UUID) {
        finishPickerRequest(requestID: requestID)
    }

    private func clearRequest() {
        activePickerRequestID = nil
        phase = .idle
    }
}

@MainActor
final class QuestionBankImportRouter: ObservableObject {
    @Published private(set) var pendingRequests: [QuestionBankFileRequest] = []

    var pendingRequestIDs: [UUID] { pendingRequests.map(\.id) }

    func receive(_ url: URL) {
        guard url.isFileURL else { return }
        pendingRequests.append(QuestionBankFileRequest(id: UUID(), url: url))
    }

    func takeNextRequest() -> QuestionBankFileRequest? {
        guard !pendingRequests.isEmpty else { return nil }
        return pendingRequests.removeFirst()
    }
}

@MainActor
struct QuestionBankDocumentPicker: UIViewControllerRepresentable {
    let requestID: UUID
    let onPick: (UUID, [URL]) -> Void
    let onCancel: (UUID) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.json, .zip],
            asCopy: true
        )
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(requestID: requestID, onPick: onPick, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let requestID: UUID
        private let onPick: (UUID, [URL]) -> Void
        private let onCancel: (UUID) -> Void

        init(requestID: UUID, onPick: @escaping (UUID, [URL]) -> Void, onCancel: @escaping (UUID) -> Void) {
            self.requestID = requestID
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(requestID, urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel(requestID)
        }
    }
}
