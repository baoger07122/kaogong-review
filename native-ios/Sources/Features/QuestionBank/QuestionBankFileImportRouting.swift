import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers
import UIKit

struct QuestionBankFileRequest: Identifiable, Equatable {
    let id: UUID
    let url: URL
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
            forOpeningContentTypes: [.zip, .data, .item],
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
