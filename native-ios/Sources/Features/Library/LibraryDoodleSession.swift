import SwiftUI

@MainActor
final class LibraryDoodleSession: ObservableObject {
    @Published var isPresented = false
    let canvas = LibraryDoodleCanvasState()
    private var saveHandler: ((String) -> Void)?

    func present(
        drawingData: String,
        legacyPreviewDataURL: String,
        onSave: @escaping (String) -> Void
    ) {
        guard !isPresented else { return }
        canvas.drawingData = drawingData
        canvas.legacyPreviewDataURL = legacyPreviewDataURL
        saveHandler = onSave
        canvas.controller.prepareForPresentation()

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
    }

    func dismiss() {
        guard isPresented else { return }
        saveHandler?(canvas.drawingData)
        canvas.controller.showSettings = false

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
        saveHandler = nil
        canvas.legacyPreviewDataURL = ""
    }
}

@MainActor
final class LibraryDoodleCanvasState: ObservableObject {
    @Published var drawingData = ""
    @Published var legacyPreviewDataURL = ""
    let controller = PencilDrawingController()
}

struct LibraryDoodleOverlay: View {
    @ObservedObject var session: LibraryDoodleSession
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    @ObservedObject private var controller: PencilDrawingController

    init(session: LibraryDoodleSession) {
        self.session = session
        _canvas = ObservedObject(wrappedValue: session.canvas)
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Lives above the complete NavigationStack. The genuine system back
                // control remains unchanged underneath and cannot receive input.
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())

                NativePencilDrawingEditor(
                    encodedData: $canvas.drawingData,
                    legacyPreviewDataURL: canvas.legacyPreviewDataURL,
                    transparentBackground: true,
                    toolbarAtTop: false,
                    controller: controller,
                    onClose: session.dismiss
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

                VStack(spacing: 0) {
                    HStack {
                        Spacer(minLength: 0)
                        toolbar
                    }
                    .padding(.top, max(proxy.safeAreaInsets.top + 5, 28))
                    .padding(.trailing, proxy.safeAreaInsets.trailing + 12)
                    Spacer(minLength: 0)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("library-doodle-root-overlay")
    }

    private var toolbar: some View {
        NativeDoodleToolbarCapsule {
            toolbarButton("xmark", label: "退出涂鸦", action: session.dismiss)
                .accessibilityIdentifier("library-doodle-close")
            toolbarButton(
                controller.eraser ? "eraser.fill" : "eraser",
                label: "橡皮擦",
                active: controller.eraser,
                action: controller.toggleEraser
            )
            toolbarButton("arrow.uturn.backward", label: "撤销", action: controller.undo)
            toolbarButton("trash", label: "清空涂鸦", action: controller.requestClear)
            toolbarButton(
                "paintpalette",
                label: controller.showSettings ? "收起画笔调节" : "展开画笔调节",
                active: controller.showSettings
            ) {
                withAnimation(.easeInOut(duration: 0.20)) {
                    controller.showSettings.toggle()
                }
            }
            toolbarButton(
                "hand.draw",
                label: controller.fingerDrawingEnabled ? "关闭手指涂鸦" : "开启手指涂鸦",
                active: controller.fingerDrawingEnabled
            ) {
                controller.fingerDrawingEnabled.toggle()
            }
        }
    }

    private func toolbarButton(
        _ systemImage: String,
        label: String,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? AppTheme.accent : Color.primary)
                .frame(width: 32, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
