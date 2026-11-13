import ImageIO
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

@MainActor
struct LibraryInlineNotePhotoPicker: UIViewControllerRepresentable {
    let requestID: UUID
    let onFinish: (UUID, NSItemProvider?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(requestID: requestID, onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        configuration.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: PHPickerViewController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let requestID: UUID
        private let onFinish: (UUID, NSItemProvider?) -> Void
        private var didFinish = false

        init(requestID: UUID, onFinish: @escaping (UUID, NSItemProvider?) -> Void) {
            self.requestID = requestID
            self.onFinish = onFinish
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            guard !didFinish else { return }
            didFinish = true
            let provider = results.first?.itemProvider
            let requestID = self.requestID
            picker.dismiss(animated: true) { [onFinish] in onFinish(requestID, provider) }
        }
    }
}

enum LibraryInlineNotePhotoCodec {
    static let maximumRoundTripBytes = 2_900_000
    private static let maximumSourceBytes = 96 * 1024 * 1024

    static func jpegData(from sourceData: Data) throws -> Data {
        guard !sourceData.isEmpty, sourceData.count <= maximumSourceBytes else {
            throw LibraryInlineNotePhotoError.tooLarge
        }
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil) else {
            throw LibraryInlineNotePhotoError.decodeFailed
        }
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1_600
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw LibraryInlineNotePhotoError.decodeFailed
        }

        for quality in [0.82, 0.68, 0.54, 0.40, 0.30] {
            guard let destinationData = CFDataCreateMutable(kCFAllocatorDefault, 0),
                  let destination = CGImageDestinationCreateWithData(
                    destinationData,
                    UTType.jpeg.identifier as CFString,
                    1,
                    nil
                  ) else {
                throw LibraryInlineNotePhotoError.encodeFailed
            }
            CGImageDestinationAddImage(
                destination,
                image,
                [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
            )
            guard CGImageDestinationFinalize(destination) else {
                throw LibraryInlineNotePhotoError.encodeFailed
            }
            let jpeg = destinationData as Data
            if jpeg.count <= maximumRoundTripBytes { return jpeg }
        }
        throw LibraryInlineNotePhotoError.tooLarge
    }
}
