import SwiftUI

@MainActor
final class LibraryDoodleSession: ObservableObject {
    @Published var isPresented = false
    @Published var saveError: String?
    @Published private(set) var targetRecordID: String?
    let canvas = LibraryDoodleCanvasState()
    private var saveHandler: ((String, Bool) -> String?)?
    private var isDismissing = false

    func present(
        targetRecordID: String,
        drawingData: String,
        legacyPreviewDataURL: String,
        onSave: @escaping (String, Bool) -> String?
    ) {
        guard !isPresented else { return }
        saveError = nil
        isDismissing = false
        self.targetRecordID = targetRecordID
        canvas.drawingData = drawingData
        canvas.legacyPreviewDataURL = legacyPreviewDataURL
        saveHandler = onSave
        let preparationStart = ProcessInfo.processInfo.systemUptime
        canvas.controller.prepareForPresentation()
        LibraryPerformanceLog.mark("doodle.present.prepare", since: preparationStart)

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
        LibraryPerformanceLog.mark("doodle.overlay-state", since: preparationStart)
    }

    func dismiss() {
        guard isPresented, !isDismissing else { return }
        isDismissing = true
        saveError = nil
        let handler = saveHandler
        let closeStart = ProcessInfo.processInfo.systemUptime
        LibraryPerformanceLog.mark("doodle.close-tap", since: closeStart)
        let completeSnapshot: () -> Void = { [weak self] in
            guard let self, self.isPresented else { return }
            let drawingData = self.canvas.drawingData
            let legacyPreviewCleared = self.canvas.controller.legacyPreviewCleared
            LibraryPerformanceLog.mark("doodle.drawing-snapshot", since: closeStart)

            // The canvas can disappear as soon as the final snapshot exists. The
            // record save is deliberately scheduled after the state change so a
            // JSON/SwiftData write cannot block the visible close feedback.
            self.finishDismissal()
            LibraryPerformanceLog.mark("doodle.overlay-hidden", since: closeStart)

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let saveStart = ProcessInfo.processInfo.systemUptime
                if let error = handler?(drawingData, legacyPreviewCleared) {
                    self.saveError = error
                    self.saveHandler = handler
                    self.isDismissing = false
                    self.isPresented = true
                    return
                }
                LibraryPerformanceLog.mark("doodle.save-handler", since: saveStart)
                self.saveHandler = nil
                self.isDismissing = false
            }
        }

        if canvas.controller.hasPendingDrawingPublish {
            canvas.controller.commit(completeSnapshot)
        } else {
            // Every completed stroke already updates drawingData. Avoid a second
            // full PKDrawing serialization when there is no pending stroke.
            completeSnapshot()
        }
    }

    private func finishDismissal() {
        canvas.controller.showSettings = false

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
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
    @ObservedObject private var controller: PencilDrawingController

    init(session: LibraryDoodleSession) {
        self.session = session
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                // The dimmer and toolbar live above the complete NavigationStack,
                // while the drawing surface is mounted inside the detail ScrollView
                // so both content and strokes share the same coordinate space.
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                toolbar
                    .padding(.top, max(proxy.safeAreaInsets.top + 5, 28))
                    .padding(.trailing, proxy.safeAreaInsets.trailing + 12)

                if let saveError = session.saveError {
                    Text(saveError)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.danger.opacity(0.9), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 18)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(session.isPresented)
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

/// Mounts PencilKit in the detail page's content coordinate space. The view is
/// attached to the scroll content instead of the window overlay; scrolling
/// therefore moves the text, images, and strokes together without serializing
/// the drawing on every offset change.
struct LibraryDoodleContentLayer: View {
    @ObservedObject var session: LibraryDoodleSession
    let targetRecordID: String
    var minimumCanvasHeight: CGFloat = 260
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    @ObservedObject private var controller: PencilDrawingController

    init(session: LibraryDoodleSession, targetRecordID: String, minimumCanvasHeight: CGFloat = 260) {
        self.session = session
        self.targetRecordID = targetRecordID
        self.minimumCanvasHeight = minimumCanvasHeight
        _canvas = ObservedObject(wrappedValue: session.canvas)
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    var body: some View {
        if session.targetRecordID == targetRecordID {
            GeometryReader { proxy in
                NativePencilDrawingEditor(
                    encodedData: $canvas.drawingData,
                    legacyPreviewDataURL: canvas.legacyPreviewDataURL,
                    transparentBackground: true,
                    toolbarAtTop: false,
                    isActive: session.isPresented,
                    minimumCanvasHeight: minimumCanvasHeight,
                    controller: controller,
                    onClose: session.dismiss
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: minimumCanvasHeight)
            .contentShape(Rectangle())
            .opacity(session.isPresented ? 1 : 0)
            .allowsHitTesting(session.isPresented)
        }
    }
}
