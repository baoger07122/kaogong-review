import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct QuestionBankFileRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
}

/// Owns the picker callback hand-off separately from sheet dismissal. A document
/// picker may send its delegate callback before SwiftUI has finished updating the
/// sheet presentation, so the selected URL must be queued and consumed exactly
/// once by the import flow.
@MainActor
final class QuestionBankImportSelectionCoordinator: ObservableObject {
    struct Selection: Equatable {
        let id: UUID
        let url: URL
    }

    private(set) var activePickerRequestID: UUID?
    private(set) var pendingSelection: Selection?
    private var handledRequestIDs = Set<UUID>()

    var hasActivePickerRequest: Bool { activePickerRequestID != nil }
    var hasPendingSelection: Bool { pendingSelection != nil }

    @discardableResult
    func beginPicker() -> UUID {
        let id = UUID()
        activePickerRequestID = id
        pendingSelection = nil
        handledRequestIDs.removeAll(keepingCapacity: true)
        return id
    }

    @discardableResult
    func receivePickedURL(_ url: URL) -> Selection? {
        guard let requestID = activePickerRequestID,
              !handledRequestIDs.contains(requestID),
              pendingSelection == nil,
              url.isFileURL else { return nil }
        handledRequestIDs.insert(requestID)
        let selection = Selection(id: requestID, url: url)
        pendingSelection = selection
        return selection
    }

    func takePendingSelection() -> Selection? {
        guard let pendingSelection else { return nil }
        self.pendingSelection = nil
        return pendingSelection
    }

    func finishPickerRequest() {
        activePickerRequestID = nil
        pendingSelection = nil
    }

    func pickerWasDismissed() {
        activePickerRequestID = nil
    }

    func cancelPickerRequest() {
        finishPickerRequest()
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
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

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
        Coordinator(onPick: onPick, onCancel: onCancel)
    }

    @MainActor
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let onPick: ([URL]) -> Void
        private let onCancel: () -> Void

        init(onPick: @escaping ([URL]) -> Void, onCancel: @escaping () -> Void) {
            self.onPick = onPick
            self.onCancel = onCancel
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls)
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onCancel()
        }
    }
}
