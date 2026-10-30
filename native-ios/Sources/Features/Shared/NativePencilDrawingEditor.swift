import PencilKit
import SwiftUI
import UIKit

private enum PencilActionKind: Equatable { case undo, redo, clear, commit }
private struct PencilAction {
    let id = UUID()
    let kind: PencilActionKind
    let completion: (() -> Void)?

    init(kind: PencilActionKind, completion: (() -> Void)? = nil) {
        self.kind = kind
        self.completion = completion
    }
}

private struct PencilDrawingPublishSnapshot {
    let id: UUID
    let drawing: PKDrawing
    let drawingRevision: Int
    let loadGeneration: Int
    let controllerLoadRevision: Int
    var includesUserEdit: Bool
    var completions: [() -> Void]
}

private enum PencilToolMemory {
    static let color = "nativePencil.color"
    static let width = "nativePencil.width"
    static let eraserWidth = "nativePencil.eraserWidth"
    static let activeTool = "nativePencil.activeTool"

    static func colorName(_ color: UIColor) -> String {
        if color.isEqual(UIColor.systemRed) { return "red" }
        if color.isEqual(UIColor.systemBlue) { return "blue" }
        if color.isEqual(UIColor.systemGreen) { return "green" }
        return "black"
    }

    static func color(_ name: String?) -> UIColor {
        switch name {
        case "red": .systemRed
        case "blue": .systemBlue
        case "green": .systemGreen
        default: .black
        }
    }
}

final class PencilDrawingController: ObservableObject {
    @Published var color: UIColor
    @Published var width: CGFloat
    @Published var eraserWidth: CGFloat
    @Published var eraser: Bool
    @Published var fingerDrawingEnabled = false
    @Published var showSettings = false
    @Published var legacyPreviewCleared = false
    // This is a save barrier read by LibraryDoodleSession, not display state.
    // Publishing every PencilKit point caused SwiftUI to re-run updateUIView
    // for the active canvas throughout a stroke.
    fileprivate(set) var hasPendingDrawingPublish = false
    @Published var canvasReady = false
    @Published var canvasLoadError: String?
    @Published fileprivate(set) var drawingLoadRevision = 0
    @Published private(set) var userDrawingRevision = 0
    @Published fileprivate var action: PencilAction?

    private let defaults: UserDefaults
    private var previousPenColor: UIColor
    private var previousPenWidth: CGFloat
    private var restoreLegacyOnNextUndo = false
    private var pendingCommitCompletions: [() -> Void] = []
    private var decodedDrawingKey: String?
    private var decodedDrawing: PKDrawing?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let savedColor = PencilToolMemory.color(defaults.string(forKey: PencilToolMemory.color))
        let savedWidth = (defaults.object(forKey: PencilToolMemory.width) as? NSNumber)?.doubleValue ?? 4
        let savedEraserWidth = (defaults.object(forKey: PencilToolMemory.eraserWidth) as? NSNumber)?.doubleValue ?? 28
        color = savedColor
        width = CGFloat(savedWidth)
        eraserWidth = CGFloat(savedEraserWidth)
        eraser = defaults.string(forKey: PencilToolMemory.activeTool) == "eraser"
        previousPenColor = savedColor
        previousPenWidth = CGFloat(savedWidth)
    }

    func selectPen(color value: UIColor) {
        color = value
        previousPenColor = value
        previousPenWidth = width
        eraser = false
        persist()
    }

    func selectWidth(_ value: CGFloat) {
        width = value
        previousPenWidth = value
        eraser = false
        persist()
    }

    func selectEraserWidth(_ value: CGFloat) {
        eraserWidth = value
        eraser = true
        persist()
    }

    func toggleEraser() {
        if eraser {
            color = previousPenColor
            width = previousPenWidth
            eraser = false
        } else {
            previousPenColor = color
            previousPenWidth = width
            eraser = true
        }
        persist()
    }

    func undo() {
        guard action == nil else { return }
        if restoreLegacyOnNextUndo {
            legacyPreviewCleared = false
            restoreLegacyOnNextUndo = false
        }
        action = PencilAction(kind: .undo)
    }

    func requestClear() {
        guard action == nil else { return }
        restoreLegacyOnNextUndo = !legacyPreviewCleared
        legacyPreviewCleared = true
        action = PencilAction(kind: .clear)
    }

    func commit(_ completion: @escaping () -> Void) {
        if action == nil {
            action = PencilAction(kind: .commit, completion: completion)
        } else {
            pendingCommitCompletions.append(completion)
        }
    }

    func finishAction(_ actionID: UUID) {
        guard action?.id == actionID else { return }
        if pendingCommitCompletions.isEmpty {
            action = nil
        } else {
            action = PencilAction(kind: .commit, completion: pendingCommitCompletions.removeFirst())
        }
    }

    private func cancelPendingActions() {
        var completions = pendingCommitCompletions
        if let completion = action?.completion { completions.append(completion) }
        pendingCommitCompletions.removeAll()
        action = nil
        guard !completions.isEmpty else { return }
        DispatchQueue.main.async {
            completions.forEach { $0() }
        }
    }

    func prepareForPresentation() {
        cancelPendingActions()
        drawingLoadRevision += 1
        showSettings = false
        fingerDrawingEnabled = false
        legacyPreviewCleared = false
        restoreLegacyOnNextUndo = false
        hasPendingDrawingPublish = false
        canvasReady = false
        canvasLoadError = nil
    }

    func beginDrawingReload() {
        cancelPendingActions()
        drawingLoadRevision += 1
        hasPendingDrawingPublish = false
        canvasReady = false
        canvasLoadError = nil
    }

    func cachedDrawing(for encoded: String) -> PKDrawing? {
        guard decodedDrawingKey == encoded else { return nil }
        return decodedDrawing
    }

    func remember(_ drawing: PKDrawing, encoded: String) {
        decodedDrawingKey = encoded
        decodedDrawing = drawing
    }

    func invalidateDecodedDrawing() {
        decodedDrawingKey = nil
        decodedDrawing = nil
    }

    func noteUserDrawingPublished() {
        userDrawingRevision &+= 1
    }

    private func persist() {
        let selectionStart = ProcessInfo.processInfo.systemUptime
        defaults.set(PencilToolMemory.colorName(previousPenColor), forKey: PencilToolMemory.color)
        defaults.set(Double(previousPenWidth), forKey: PencilToolMemory.width)
        defaults.set(Double(eraserWidth), forKey: PencilToolMemory.eraserWidth)
        defaults.set(eraser ? "eraser" : "pen", forKey: PencilToolMemory.activeTool)
        LibraryPerformanceLog.mark("doodle.tool-selection", since: selectionStart)
    }
}

struct NativePencilDrawingEditor: View {
    @Binding var encodedData: String
    let legacyPreviewDataURL: String
    let transparentBackground: Bool
    let toolbarAtTop: Bool
    let isActive: Bool
    let minimumCanvasHeight: CGFloat
    let onClose: (() -> Void)?
    @StateObject private var controller: PencilDrawingController
    @State private var decodedLegacyImage: UIImage?

    init(
        encodedData: Binding<String>,
        legacyPreviewDataURL: String = "",
        transparentBackground: Bool = false,
        toolbarAtTop: Bool = false,
        isActive: Bool = true,
        minimumCanvasHeight: CGFloat = 260,
        controller: PencilDrawingController? = nil,
        onClose: (() -> Void)? = nil
    ) {
        _encodedData = encodedData
        self.legacyPreviewDataURL = legacyPreviewDataURL
        self.transparentBackground = transparentBackground
        self.toolbarAtTop = toolbarAtTop
        self.isActive = isActive
        self.minimumCanvasHeight = minimumCanvasHeight
        self.onClose = onClose
        _controller = StateObject(wrappedValue: controller ?? PencilDrawingController())
    }

    var body: some View {
        Group {
            if #available(iOS 17.5, *) {
                editorContent
                    .onPencilSqueeze { phase in
                        if case .ended(_) = phase {
                            controller.toggleEraser()
                        }
                    }
            } else {
                editorContent
            }
        }
        .task(id: legacyPreviewDataURL) {
            guard let marker = legacyPreviewDataURL.range(of: "base64,") else {
                decodedLegacyImage = nil
                return
            }
            let encoded = String(legacyPreviewDataURL[marker.upperBound...])
            let imageData = await Task.detached(priority: .utility) {
                Data(base64Encoded: encoded)
            }.value
            guard !Task.isCancelled else { return }
            decodedLegacyImage = imageData.flatMap { UIImage(data: $0) }
        }
        .onChange(of: controller.action?.id) { _, _ in
            if case .clear? = controller.action?.kind {
                // Keep the SwiftUI source of truth empty even if the UIKit delegate
                // callback arrives after the drawing overlay has been dismissed.
                encodedData = ""
            }
        }
    }

    @ViewBuilder private var editorContent: some View {
        if transparentBackground {
            floatingEditor
        } else {
            classicEditor
        }
    }

    private var floatingEditor: some View {
        canvas
            .overlay(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if controller.showSettings {
                        penSettingsPanel
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.16), value: controller.showSettings)
            }
    }

    private var classicEditor: some View {
        VStack(spacing: 0) {
            if toolbarAtTop {
                toolStrip
                Divider()
            }
            canvas
            if decodedLegacyImage != nil, !controller.legacyPreviewCleared {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                    Text("已载入 Web 旧涂鸦，可在底图上继续标注")
                    Spacer()
                }
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Color.primary.opacity(0.035))
            }
            if !toolbarAtTop {
                Divider()
                toolStrip
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
    }

    private var canvas: some View {
        ZStack {
            (transparentBackground ? Color.clear : Color.white)
                .contentShape(Rectangle())
            if let decodedLegacyImage, !controller.legacyPreviewCleared {
                Image(uiImage: decodedLegacyImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .accessibilityLabel("Web 旧涂鸦底图")
            }
            PencilCanvasRepresentable(
                encodedData: $encodedData,
                controller: controller,
                drawingLoadRevision: controller.drawingLoadRevision,
                color: controller.color,
                width: controller.width,
                eraser: controller.eraser,
                eraserWidth: controller.eraserWidth,
                fingerDrawingEnabled: controller.fingerDrawingEnabled,
                scrollEnabled: !transparentBackground,
                isActive: isActive,
                action: $controller.action
            )
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: minimumCanvasHeight)
    }

    private var penSettingsPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Text("画笔调节")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("取消") {
                    controller.showSettings = false
                }
                .font(AppTheme.inputFont)
            }

            HStack(spacing: 18) {
                ForEach([UIColor.black, .systemRed, .systemBlue, .systemGreen], id: \.description) { value in
                    Button {
                        controller.selectPen(color: value)
                    } label: {
                        Circle()
                            .fill(Color(uiColor: value))
                            .frame(width: 34, height: 34)
                            .overlay(
                                Circle()
                                    .stroke(
                                        !controller.eraser && controller.color == value ? AppTheme.accent : Color.primary.opacity(0.10),
                                        lineWidth: !controller.eraser && controller.color == value ? 3 : 1
                                    )
                                    .padding(-3)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("选择画笔颜色")
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Text("画笔粗细").font(AppTheme.fieldLabelFont).foregroundStyle(.secondary)
                Picker("画笔粗细", selection: penWidthBinding) {
                    Text("细").tag(CGFloat(2))
                    Text("中").tag(CGFloat(4))
                    Text("粗").tag(CGFloat(8))
                }
                .pickerStyle(.segmented)

                Text("橡皮擦大小").font(AppTheme.fieldLabelFont).foregroundStyle(.secondary)
                Picker("橡皮擦大小", selection: eraserWidthBinding) {
                    Text("小").tag(CGFloat(14))
                    Text("中").tag(CGFloat(28))
                    Text("大").tag(CGFloat(44))
                }
                .pickerStyle(.segmented)
                Text("只擦除橡皮擦圆圈内的部分，笔画其他位置会保留。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 310)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24))
        .shadow(color: Color.black.opacity(0.10), radius: 18, y: -4)
    }

    private var toolStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([UIColor.black, .systemRed, .systemBlue, .systemGreen], id: \.description) { value in
                        Button {
                            controller.selectPen(color: value)
                        } label: {
                            Circle().fill(Color(uiColor: value)).frame(width: 23, height: 23)
                                .overlay(
                                    Circle()
                                        .stroke(!controller.eraser && controller.color == value ? AppTheme.accent : .clear, lineWidth: 2.5)
                                        .padding(-3)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    Picker("粗细", selection: penWidthBinding) {
                        Text("细").tag(CGFloat(2))
                        Text("中").tag(CGFloat(4))
                        Text("粗").tag(CGFloat(8))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                    Picker("橡皮擦", selection: eraserWidthBinding) {
                        Text("小").tag(CGFloat(14))
                        Text("中").tag(CGFloat(28))
                        Text("大").tag(CGFloat(44))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 120)
                }
            }
            Spacer(minLength: 4)
            if let onClose {
                toolButton("xmark", active: false, accessibilityLabel: "退出涂鸦", action: onClose)
            }
            toolButton(controller.eraser ? "eraser.fill" : "eraser", active: controller.eraser, accessibilityLabel: "橡皮擦") {
                controller.toggleEraser()
            }
            .accessibilityHint("只擦除橡皮擦范围内的笔迹")
            toolButton("arrow.uturn.backward", active: false, accessibilityLabel: "撤销") {
                controller.undo()
            }
            toolButton("trash", active: false, accessibilityLabel: "清空涂鸦") {
                controller.requestClear()
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private var penWidthBinding: Binding<CGFloat> {
        Binding(get: { controller.width }, set: { value in
            controller.selectWidth(value)
        })
    }

    private var eraserWidthBinding: Binding<CGFloat> {
        Binding(get: { controller.eraserWidth }, set: { value in
            controller.selectEraserWidth(value)
        })
    }

    private func toolButton(
        _ image: String,
        active: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 36, height: 34)
                .background(active ? AppTheme.accent : Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var encodedData: String
    let controller: PencilDrawingController
    let drawingLoadRevision: Int
    let color: UIColor
    let width: CGFloat
    let eraser: Bool
    let eraserWidth: CGFloat
    let fingerDrawingEnabled: Bool
    let scrollEnabled: Bool
    let isActive: Bool
    @Binding var action: PencilAction?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self, controller: controller) }

    func makeUIView(context: Context) -> InteractivePencilCanvasView {
        let canvasStart = ProcessInfo.processInfo.systemUptime
        let canvas = InteractivePencilCanvasView()
        canvas.shouldBecomeFirstResponder = isActive
        canvas.isDrawingReady = false
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = fingerDrawingEnabled ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = isActive && context.coordinator.canvasReady
        if #available(iOS 18.0, *) { canvas.isDrawingEnabled = true }
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = scrollEnabled ? 0.5 : 1
        canvas.maximumZoomScale = scrollEnabled ? 3 : 1
        canvas.bouncesZoom = true
        // Library doodles are hosted inside the detail ScrollView. Keeping the
        // PKCanvasView itself stationary avoids a second, independent content
        // offset that would separate strokes from the question text.
        canvas.isScrollEnabled = scrollEnabled
        canvas.alwaysBounceHorizontal = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled
        canvas.isMultipleTouchEnabled = true
        canvas.configureEraserCursor(
            enabled: isActive && eraser && context.coordinator.canvasReady,
            width: eraserWidth
        )

        context.coordinator.loadDrawing(encodedData, revision: drawingLoadRevision, on: canvas)
        context.coordinator.updateTool(canvas)
        LibraryPerformanceLog.mark("doodle.canvas-create", since: canvasStart)
        return canvas
    }

    func updateUIView(_ canvas: InteractivePencilCanvasView, context: Context) {
        context.coordinator.parent = self
        canvas.configureEraserCursor(
            enabled: isActive && eraser && context.coordinator.canvasReady,
            width: eraserWidth
        )
        canvas.shouldBecomeFirstResponder = isActive
        canvas.isUserInteractionEnabled = isActive && context.coordinator.canvasReady
        if !isActive {
            canvas.resignFirstResponder()
            return
        }
        context.coordinator.updateTool(canvas)
        canvas.drawingPolicy = fingerDrawingEnabled ? .anyInput : .pencilOnly
        if #available(iOS 18.0, *) { canvas.isDrawingEnabled = true }
        canvas.isScrollEnabled = scrollEnabled
        canvas.minimumZoomScale = scrollEnabled ? 0.5 : 1
        canvas.maximumZoomScale = scrollEnabled ? 3 : 1
        canvas.alwaysBounceHorizontal = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled
        canvas.isMultipleTouchEnabled = true
        if canvas.window != nil, !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        if let action, context.coordinator.lastActionID != action.id {
            context.coordinator.lastActionID = action.id
            var waitsForPublish = false
            switch action.kind {
            case .undo:
                canvas.undoManager?.undo()
                context.coordinator.publish(canvas, userInitiated: true)
            case .redo:
                canvas.undoManager?.redo()
                context.coordinator.publish(canvas, userInitiated: true)
            case .clear:
                let previousDrawing = canvas.drawing
                canvas.undoManager?.registerUndo(withTarget: context.coordinator) { coordinator in
                    coordinator.restore(previousDrawing, on: canvas)
                }
                canvas.undoManager?.setActionName("清空涂鸦")
                canvas.drawing = PKDrawing()
                context.coordinator.publish(canvas, userInitiated: true)
            case .commit:
                waitsForPublish = true
                context.coordinator.publish(canvas) {
                    self.controller.finishAction(action.id)
                    action.completion?()
                }
            }
            if !waitsForPublish {
                DispatchQueue.main.async {
                    self.controller.finishAction(action.id)
                    action.completion?()
                }
            }
        }
        context.coordinator.loadDrawing(encodedData, revision: drawingLoadRevision, on: canvas)
    }

    static func dismantleUIView(_ uiView: InteractivePencilCanvasView, coordinator: Coordinator) {
        uiView.configureEraserCursor(enabled: false, width: 0)
        coordinator.flushForDismantle(uiView)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasRepresentable
        let controller: PencilDrawingController
        var lastEncoded = ""
        var lastActionID: UUID?
        var drawingChanged = false
        private var drawingRevision = 0
        private var loadGeneration = 0
        private var requestedEncoded: String?
        private var requestedRevision: Int?
        private var decodeToken = UUID()
        var canvasReady = false
        private var pendingPublish: DispatchWorkItem?
        private var activePublication: PencilDrawingPublishSnapshot?
        private var latestPendingPublication: PencilDrawingPublishSnapshot?
        private let publishQueue = DispatchQueue(label: "QuestionBank.PencilDrawing.publish", qos: .userInitiated)
        private var configuredEraser: Bool?
        private var configuredColor: UIColor?
        private var configuredWidth: CGFloat?
        private var configuredEraserWidth: CGFloat?

        init(parent: PencilCanvasRepresentable, controller: PencilDrawingController) {
            self.parent = parent
            self.controller = controller
        }

        func updateTool(_ canvas: PKCanvasView) {
            let unchanged = configuredEraser == parent.eraser
                && configuredColor?.isEqual(parent.color) == true
                && configuredWidth == parent.width
                && configuredEraserWidth == parent.eraserWidth
            guard !unchanged else { return }
            canvas.tool = parent.eraser
                ? PKEraserTool(.bitmap, width: parent.eraserWidth)
                : PKInkingTool(.pen, color: parent.color, width: parent.width)
            configuredEraser = parent.eraser
            configuredColor = parent.color
            configuredWidth = parent.width
            configuredEraserWidth = parent.eraserWidth
        }

        func loadDrawing(_ encoded: String, revision: Int, on canvas: InteractivePencilCanvasView) {
            guard requestedEncoded != encoded || requestedRevision != revision else { return }
            requestedEncoded = encoded
            requestedRevision = revision
            loadGeneration &+= 1
            pendingPublish?.cancel()
            pendingPublish = nil
            let cancelledCompletions = latestPendingPublication?.completions ?? []
            latestPendingPublication = nil
            canvasReady = false
            controller.canvasReady = false
            controller.canvasLoadError = nil
            canvas.isUserInteractionEnabled = false
            canvas.isDrawingReady = false
            drawingChanged = false
            controller.hasPendingDrawingPublish = false
            if !cancelledCompletions.isEmpty {
                DispatchQueue.main.async {
                    cancelledCompletions.forEach { $0() }
                }
            }
            let token = UUID()
            decodeToken = token
            let decodeStart = ProcessInfo.processInfo.systemUptime

            if encoded.isEmpty {
                DispatchQueue.main.async { [weak self, weak canvas] in
                    guard let self, let canvas, self.decodeToken == token,
                          self.controller.drawingLoadRevision == revision else { return }
                    let drawing = self.controller.cachedDrawing(for: encoded) ?? PKDrawing()
                    self.controller.remember(drawing, encoded: encoded)
                    canvas.drawing = drawing
                    self.lastEncoded = ""
                    self.canvasReady = true
                    self.controller.canvasReady = true
                    self.controller.canvasLoadError = nil
                    canvas.isDrawingReady = true
                    canvas.isUserInteractionEnabled = self.parent.isActive
                    if self.parent.isActive {
                        canvas.becomeFirstResponder()
                    }
                    self.controller.hasPendingDrawingPublish = false
                    LibraryPerformanceLog.mark("doodle.canvas.decode.empty", since: decodeStart)
                }
                return
            }

            if let drawing = controller.cachedDrawing(for: encoded) {
                DispatchQueue.main.async { [weak self, weak canvas] in
                    guard let self, let canvas, self.decodeToken == token,
                          self.controller.drawingLoadRevision == revision else { return }
                    canvas.drawing = drawing
                    self.lastEncoded = encoded
                    self.canvasReady = true
                    self.controller.canvasReady = true
                    self.controller.canvasLoadError = nil
                    canvas.isDrawingReady = true
                    canvas.isUserInteractionEnabled = self.parent.isActive
                    if self.parent.isActive { canvas.becomeFirstResponder() }
                    self.controller.hasPendingDrawingPublish = false
                    LibraryPerformanceLog.mark("doodle.canvas.cache-attach", since: decodeStart)
                }
                return
            }

            DispatchQueue.global(qos: .userInitiated).async { [weak self, weak canvas] in
                let drawing = Data(base64Encoded: encoded).flatMap { try? PKDrawing(data: $0) }
                LibraryPerformanceLog.mark("doodle.canvas.decode", since: decodeStart)
                DispatchQueue.main.async {
                    guard let self, let canvas, self.decodeToken == token,
                          self.controller.drawingLoadRevision == revision else { return }
                    guard let drawing else {
                        self.controller.canvasReady = false
                        self.controller.canvasLoadError = "已有涂鸦无法载入；关闭后会保留原记录。"
                        return
                    }
                    self.controller.remember(drawing, encoded: encoded)
                    canvas.drawing = drawing
                    self.lastEncoded = encoded
                    self.canvasReady = true
                    self.controller.canvasReady = true
                    self.controller.canvasLoadError = nil
                    canvas.isDrawingReady = true
                    canvas.isUserInteractionEnabled = self.parent.isActive
                    if self.parent.isActive {
                        canvas.becomeFirstResponder()
                    }
                    self.controller.hasPendingDrawingPublish = false
                    LibraryPerformanceLog.mark("doodle.canvas.attach", since: decodeStart)
                }
            }
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            guard let canvas = canvasView as? InteractivePencilCanvasView,
                  canvas.isDrawingReady, canvasReady else { return }
            drawingChanged = true
            drawingRevision += 1
            if !controller.hasPendingDrawingPublish {
                controller.hasPendingDrawingPublish = true
            }
            pendingPublish?.cancel()
            let work = DispatchWorkItem { [weak self, weak canvasView] in
                guard let self, let canvasView, self.drawingChanged else { return }
                self.publish(canvasView)
            }
            pendingPublish = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            guard drawingChanged else { return }
            pendingPublish?.cancel()
            publish(canvasView)
        }

        func publish(
            _ canvas: PKCanvasView,
            userInitiated: Bool = false,
            completion: (() -> Void)? = nil
        ) {
            pendingPublish?.cancel()
            pendingPublish = nil
            guard let interactiveCanvas = canvas as? InteractivePencilCanvasView,
                  interactiveCanvas.isDrawingReady,
                  canvasReady,
                  controller.canvasReady else {
                completion?()
                return
            }
            let revision = drawingRevision
            let targetRevision = controller.drawingLoadRevision
            let generation = loadGeneration
            let includesUserEdit = userInitiated || drawingChanged

            if var active = activePublication,
               active.drawingRevision == revision,
               active.loadGeneration == generation,
               active.controllerLoadRevision == targetRevision,
               latestPendingPublication == nil {
                active.includesUserEdit = active.includesUserEdit || includesUserEdit
                if let completion { active.completions.append(completion) }
                activePublication = active
                controller.hasPendingDrawingPublish = true
                return
            }
            if var pending = latestPendingPublication,
               pending.drawingRevision == revision,
               pending.loadGeneration == generation,
               pending.controllerLoadRevision == targetRevision {
                pending.includesUserEdit = pending.includesUserEdit || includesUserEdit
                if let completion { pending.completions.append(completion) }
                latestPendingPublication = pending
                return
            }

            var completions = latestPendingPublication?.completions ?? []
            latestPendingPublication = nil
            if var active = activePublication,
               active.loadGeneration == generation,
               active.controllerLoadRevision == targetRevision {
                completions.insert(contentsOf: active.completions, at: 0)
                active.completions = []
                activePublication = active
            }
            if let completion { completions.append(completion) }

            let snapshot = PencilDrawingPublishSnapshot(
                id: UUID(),
                drawing: canvas.drawing,
                drawingRevision: revision,
                loadGeneration: generation,
                controllerLoadRevision: targetRevision,
                includesUserEdit: includesUserEdit,
                completions: completions
            )
            controller.hasPendingDrawingPublish = true
            if activePublication == nil {
                startPublication(snapshot, canvas: canvas)
            } else {
                latestPendingPublication = snapshot
            }
        }

        func flushForDismantle(_ canvas: InteractivePencilCanvasView) {
            pendingPublish?.cancel()
            pendingPublish = nil
            if let action = controller.action {
                if action.kind == .commit {
                    if lastActionID != action.id {
                        lastActionID = action.id
                        publish(canvas) {
                            self.controller.finishAction(action.id)
                            action.completion?()
                        }
                    }
                    return
                }
                controller.finishAction(action.id)
                if controller.action != nil {
                    flushForDismantle(canvas)
                    return
                }
            }
            if drawingChanged || controller.hasPendingDrawingPublish {
                publish(canvas)
            }
        }

        private func startPublication(
            _ snapshot: PencilDrawingPublishSnapshot,
            canvas: PKCanvasView?
        ) {
            activePublication = snapshot
            let serializeStart = ProcessInfo.processInfo.systemUptime
            let drawing = snapshot.drawing
            let snapshotID = snapshot.id
            publishQueue.async { [self, weak canvas] in
                let value = drawing.strokes.isEmpty ? "" : drawing.dataRepresentation().base64EncodedString()
                LibraryPerformanceLog.mark("doodle.canvas.serialize", since: serializeStart)
                DispatchQueue.main.async { [self, weak canvas] in
                    finishPublication(id: snapshotID, encoded: value, canvas: canvas)
                }
            }
        }

        private func finishPublication(
            id: UUID,
            encoded: String,
            canvas: PKCanvasView?
        ) {
            guard let completed = activePublication, completed.id == id else { return }
            activePublication = nil

            guard isCurrentPublicationTarget(completed) else {
                complete(completed.completions)
                startPendingPublicationIfCurrent(canvas: canvas)
                return
            }

            if var pending = latestPendingPublication {
                latestPendingPublication = nil
                guard isCurrentPublicationTarget(pending) else {
                    complete(completed.completions)
                    complete(pending.completions)
                    return
                }
                pending.completions.insert(contentsOf: completed.completions, at: 0)
                if pending.drawingRevision == drawingRevision {
                    startPublication(pending, canvas: canvas)
                } else if let canvas {
                    startLatestPublication(from: canvas, completions: pending.completions)
                } else {
                    complete(pending.completions)
                }
                return
            }

            guard completed.drawingRevision == drawingRevision else {
                if let canvas {
                    startLatestPublication(from: canvas, completions: completed.completions)
                } else {
                    complete(completed.completions)
                }
                return
            }

            controller.remember(completed.drawing, encoded: encoded)
            if completed.includesUserEdit, encoded != lastEncoded {
                controller.noteUserDrawingPublished()
            }
            lastEncoded = encoded
            requestedEncoded = encoded
            requestedRevision = completed.controllerLoadRevision
            parent.encodedData = encoded
            drawingChanged = false
            controller.hasPendingDrawingPublish = false
            complete(completed.completions)
        }

        private func startPendingPublicationIfCurrent(canvas: PKCanvasView?) {
            guard let pending = latestPendingPublication else { return }
            latestPendingPublication = nil
            guard isCurrentPublicationTarget(pending) else {
                complete(pending.completions)
                return
            }
            if pending.drawingRevision == drawingRevision {
                startPublication(pending, canvas: canvas)
            } else if let canvas {
                startLatestPublication(from: canvas, completions: pending.completions)
            } else {
                complete(pending.completions)
            }
        }

        private func startLatestPublication(from canvas: PKCanvasView, completions: [() -> Void]) {
            guard let interactiveCanvas = canvas as? InteractivePencilCanvasView,
                  interactiveCanvas.isDrawingReady,
                  canvasReady,
                  controller.canvasReady else {
                complete(completions)
                return
            }
            startPublication(
                PencilDrawingPublishSnapshot(
                    id: UUID(),
                    drawing: canvas.drawing,
                    drawingRevision: drawingRevision,
                    loadGeneration: loadGeneration,
                    controllerLoadRevision: controller.drawingLoadRevision,
                    includesUserEdit: drawingChanged,
                    completions: completions
                ),
                canvas: canvas
            )
        }

        private func isCurrentPublicationTarget(_ snapshot: PencilDrawingPublishSnapshot) -> Bool {
            snapshot.loadGeneration == loadGeneration
                && snapshot.controllerLoadRevision == controller.drawingLoadRevision
        }

        private func complete(_ completions: [() -> Void]) {
            completions.forEach { $0() }
        }

        func restore(_ drawing: PKDrawing, on canvas: PKCanvasView) {
            canvas.drawing = drawing
            publish(canvas)
        }
    }
}

private final class InteractivePencilCanvasView: PKCanvasView, UIGestureRecognizerDelegate {
    var shouldBecomeFirstResponder = false
    var isDrawingReady = false
    private let eraserCursorLayer = CAShapeLayer()
    private var hoverRecognizer: UIHoverGestureRecognizer?
    private var hasInstalledEraserCursor = false
    private var eraserCursorEnabled = false
    private var eraserCursorWidth: CGFloat = 0
    private var eraserCursorPoint: CGPoint?
    private var eraserCursorOpacity: Float = 0.78
    private var isTouchingForErase = false

    func configureEraserCursor(enabled: Bool, width: CGFloat) {
        if enabled { installEraserCursorIfNeeded() }
        guard hasInstalledEraserCursor else { return }
        eraserCursorEnabled = enabled
        eraserCursorWidth = max(width, 0)
        if #available(iOS 16.1, *) { hoverRecognizer?.isEnabled = enabled }
        guard enabled else {
            isTouchingForErase = false
            eraserCursorPoint = nil
            eraserCursorLayer.isHidden = true
            return
        }
        redrawEraserCursor()
    }

    private func installEraserCursorIfNeeded() {
        guard !hasInstalledEraserCursor else { return }
        hasInstalledEraserCursor = true
        eraserCursorLayer.fillColor = UIColor.systemGray.withAlphaComponent(0.10).cgColor
        eraserCursorLayer.strokeColor = UIColor.label.withAlphaComponent(0.72).cgColor
        eraserCursorLayer.lineWidth = 1.5
        eraserCursorLayer.isHidden = true
        eraserCursorLayer.actions = [
            "path": NSNull(), "frame": NSNull(), "position": NSNull(), "hidden": NSNull(), "opacity": NSNull()
        ]
        layer.addSublayer(eraserCursorLayer)

        if #available(iOS 16.1, *) {
            let hover = UIHoverGestureRecognizer(target: self, action: #selector(handlePencilHover(_:)))
            hover.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
            hover.cancelsTouchesInView = false
            hover.delaysTouchesBegan = false
            hover.delaysTouchesEnded = false
            hover.delegate = self
            hover.isEnabled = eraserCursorEnabled
            addGestureRecognizer(hover)
            hoverRecognizer = hover
        }
    }

    private func showEraserCursor(at point: CGPoint, opacity: Float) {
        guard eraserCursorEnabled else { return }
        eraserCursorPoint = point
        eraserCursorOpacity = min(max(opacity, 0.25), 0.90)
        redrawEraserCursor()
    }

    private func redrawEraserCursor() {
        guard eraserCursorEnabled, let point = eraserCursorPoint else {
            eraserCursorLayer.isHidden = true
            return
        }
        eraserCursorLayer.frame = bounds
        let diameter = max(2, eraserCursorWidth * max(zoomScale, 0.1))
        let radius = diameter / 2
        let layerPoint = layer.convert(point, to: eraserCursorLayer)
        let rect = CGRect(x: layerPoint.x - radius, y: layerPoint.y - radius,
                          width: diameter, height: diameter)
        eraserCursorLayer.path = UIBezierPath(ovalIn: rect).cgPath
        eraserCursorLayer.opacity = eraserCursorOpacity
        eraserCursorLayer.isHidden = false
    }

    private func hideEraserCursor() {
        eraserCursorPoint = nil
        eraserCursorLayer.isHidden = true
    }

    @objc private func handlePencilHover(_ recognizer: UIHoverGestureRecognizer) {
        guard #available(iOS 16.1, *), eraserCursorEnabled, !isTouchingForErase else {
            hideEraserCursor()
            return
        }
        switch recognizer.state {
        case .began, .changed:
            showEraserCursor(at: recognizer.location(in: self), opacity: 0.34 + (1 - Float(recognizer.zOffset)) * 0.45)
        case .ended, .cancelled, .failed:
            hideEraserCursor()
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        gestureRecognizer === hoverRecognizer || otherGestureRecognizer === hoverRecognizer
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if eraserCursorEnabled, let touch = touches.first(where: { $0.type == .pencil }) ?? touches.first {
            isTouchingForErase = true
            showEraserCursor(at: touch.preciseLocation(in: self), opacity: 0.78)
        }
        super.touchesBegan(touches, with: event)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesMoved(touches, with: event)
        if eraserCursorEnabled, let touch = touches.first(where: { $0.type == .pencil }) ?? touches.first {
            showEraserCursor(at: touch.preciseLocation(in: self), opacity: 0.78)
        }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        isTouchingForErase = false
        hideEraserCursor()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        isTouchingForErase = false
        hideEraserCursor()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        redrawEraserCursor()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else {
            hideEraserCursor()
            return
        }
        isUserInteractionEnabled = isDrawingReady && shouldBecomeFirstResponder
        if #available(iOS 18.0, *) { isDrawingEnabled = true }
        guard shouldBecomeFirstResponder else { return }
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }
}

enum PencilDrawingCompatibility {
    static func previewDataURL(encodedData: String) -> String {
        guard let data = Data(base64Encoded: encodedData),
              let drawing = try? PKDrawing(data: data),
              !drawing.bounds.isEmpty else { return "" }
        let bounds = drawing.bounds.insetBy(dx: -18, dy: -18)
        let image = drawing.image(from: bounds, scale: 2)
        guard let png = image.pngData() else { return "" }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
