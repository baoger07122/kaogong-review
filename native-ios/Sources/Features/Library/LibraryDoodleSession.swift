import SwiftUI
import UIKit

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
        canvas.canvasFrameInGlobal = nil
        canvas.controller.canvasReady = false
        canvas.controller.canvasLoadError = nil
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
    @Published var canvasFrameInGlobal: CGRect?
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
            let activeCanvasFrame = canvasPassThroughRect(in: proxy)
            ZStack(alignment: .topTrailing) {
                // The transparent shield blocks every underlying control while the
                // canvas loads, then leaves only the active canvas target hittable.
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)

                LibraryDoodleInteractionShield(
                    passThroughRect: activeCanvasFrame
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(controller.canvasLoadError ?? "涂鸦交互遮罩")
                .accessibilityValue(activeCanvasFrame == nil ? "canvas-loading" : "canvas-ready")
                .accessibilityIdentifier("library-doodle-interaction-shield")

                if let message = controller.canvasLoadError {
                    statusMessage(message)
                        .allowsHitTesting(false)
                } else if activeCanvasFrame == nil {
                    ProgressView("正在载入涂鸦")
                        .padding(12)
                        .background(.regularMaterial, in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

                toolbar
                    .padding(.top, max(proxy.safeAreaInsets.top + 5, 28))
                    .padding(.trailing, proxy.safeAreaInsets.trailing + 12)
                    .zIndex(1)

                if let saveError = session.saveError {
                    statusMessage(saveError)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 18)
                        .allowsHitTesting(false)
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

    private func statusMessage(_ value: String) -> some View {
        Text(value)
            .font(AppTheme.auxiliaryFont)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(AppTheme.danger.opacity(0.9), in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    private func canvasPassThroughRect(in proxy: GeometryProxy) -> CGRect? {
        guard controller.canvasReady,
              let canvasFrame = canvas.canvasFrameInGlobal else { return nil }
        let overlayFrame = proxy.frame(in: .global)
        let localFrame = CGRect(
            x: canvasFrame.minX - overlayFrame.minX,
            y: canvasFrame.minY - overlayFrame.minY,
            width: canvasFrame.width,
            height: canvasFrame.height
        )
        let visibleFrame = localFrame.intersection(CGRect(origin: .zero, size: proxy.size))
        return visibleFrame.isNull || visibleFrame.isEmpty ? nil : visibleFrame
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
                .preference(
                    key: LibraryDoodleCanvasFramePreferenceKey.self,
                    value: [targetRecordID: proxy.frame(in: .global)]
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: minimumCanvasHeight)
            .contentShape(Rectangle())
            .opacity(session.isPresented ? 1 : 0)
            .allowsHitTesting(session.isPresented)
        }
        .onPreferenceChange(LibraryDoodleCanvasFramePreferenceKey.self) { frames in
            guard session.targetRecordID == targetRecordID else { return }
            session.canvas.canvasFrameInGlobal = frames[targetRecordID]
        }
        .onDisappear {
            guard session.targetRecordID == targetRecordID else { return }
            session.canvas.canvasFrameInGlobal = nil
        }
    }
}

private struct LibraryDoodleCanvasFramePreferenceKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]

    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct LibraryDoodleInteractionShield: UIViewRepresentable {
    let passThroughRect: CGRect?

    func makeUIView(context: Context) -> ShieldView {
        let view = ShieldView()
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ view: ShieldView, context: Context) {
        view.passThroughRect = passThroughRect
    }

    final class ShieldView: UIView {
        var passThroughRect: CGRect?

        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            guard super.point(inside: point, with: event) else { return false }
            return !(passThroughRect?.contains(point) ?? false)
        }
    }
}
