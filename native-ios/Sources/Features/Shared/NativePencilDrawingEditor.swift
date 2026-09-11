import PencilKit
import SwiftUI
import UIKit

private enum PencilActionKind { case undo, redo, clear }
private struct PencilAction { let id = UUID(); let kind: PencilActionKind }

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
    @Published fileprivate var action: PencilAction?

    private let defaults: UserDefaults
    private var previousPenColor: UIColor
    private var previousPenWidth: CGFloat
    private var restoreLegacyOnNextUndo = false

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
        if restoreLegacyOnNextUndo {
            legacyPreviewCleared = false
            restoreLegacyOnNextUndo = false
        }
        action = PencilAction(kind: .undo)
    }

    func requestClear() {
        restoreLegacyOnNextUndo = !legacyPreviewCleared
        legacyPreviewCleared = true
        action = PencilAction(kind: .clear)
    }

    func prepareForPresentation() {
        showSettings = false
        fingerDrawingEnabled = false
        legacyPreviewCleared = false
        restoreLegacyOnNextUndo = false
    }

    private func persist() {
        defaults.set(PencilToolMemory.colorName(previousPenColor), forKey: PencilToolMemory.color)
        defaults.set(Double(previousPenWidth), forKey: PencilToolMemory.width)
        defaults.set(Double(eraserWidth), forKey: PencilToolMemory.eraserWidth)
        defaults.set(eraser ? "eraser" : "pen", forKey: PencilToolMemory.activeTool)
        defaults.synchronize()
    }
}

struct NativePencilDrawingEditor: View {
    @Binding var encodedData: String
    let legacyPreviewDataURL: String
    let transparentBackground: Bool
    let toolbarAtTop: Bool
    let onClose: (() -> Void)?
    @StateObject private var controller: PencilDrawingController
    @State private var eraserLocation: CGPoint?

    init(
        encodedData: Binding<String>,
        legacyPreviewDataURL: String = "",
        transparentBackground: Bool = false,
        toolbarAtTop: Bool = false,
        controller: PencilDrawingController? = nil,
        onClose: (() -> Void)? = nil
    ) {
        _encodedData = encodedData
        self.legacyPreviewDataURL = legacyPreviewDataURL
        self.transparentBackground = transparentBackground
        self.toolbarAtTop = toolbarAtTop
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
                            eraserLocation = nil
                        }
                    }
            } else {
                editorContent
            }
        }
        .onChange(of: controller.eraser) { _, enabled in
            if !enabled { eraserLocation = nil }
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
                if controller.showSettings {
                    penSettingsPanel
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.20), value: controller.showSettings)
    }

    private var classicEditor: some View {
        VStack(spacing: 0) {
            if toolbarAtTop {
                toolStrip
                Divider()
            }
            canvas
            if legacyImage != nil, !controller.legacyPreviewCleared {
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
            if let legacyImage, !controller.legacyPreviewCleared {
                Image(uiImage: legacyImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .accessibilityLabel("Web 旧涂鸦底图")
            }
            PencilCanvasRepresentable(
                encodedData: $encodedData,
                color: controller.color,
                width: controller.width,
                eraser: controller.eraser,
                eraserWidth: controller.eraserWidth,
                fingerDrawingEnabled: controller.fingerDrawingEnabled,
                scrollEnabled: !transparentBackground,
                eraserLocation: $eraserLocation,
                action: $controller.action
            )
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .zIndex(1)

            if controller.eraser, let eraserLocation {
                Circle()
                    .fill(Color.white.opacity(0.18))
                    .overlay(Circle().stroke(Color.primary.opacity(0.62), lineWidth: 1.2))
                    .frame(width: eraserCursorDiameter, height: eraserCursorDiameter)
                    .position(eraserLocation)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
    }

    private var penSettingsPanel: some View {
        VStack(spacing: 18) {
            HStack {
                Text("画笔调节")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Button("取消") {
                    withAnimation(.easeInOut(duration: 0.20)) {
                        controller.showSettings = false
                    }
                }
                .font(AppTheme.inputFont)
            }

            HStack(spacing: 18) {
                ForEach([UIColor.black, .systemRed, .systemBlue, .systemGreen], id: \.description) { value in
                    Button {
                        controller.selectPen(color: value)
                        eraserLocation = nil
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
                            eraserLocation = nil
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
                eraserLocation = nil
            }
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

    private var legacyImage: UIImage? {
        guard let marker = legacyPreviewDataURL.range(of: "base64,") else { return nil }
        let encoded = String(legacyPreviewDataURL[marker.upperBound...])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }

    private var penWidthBinding: Binding<CGFloat> {
        Binding(get: { controller.width }, set: { value in
            controller.selectWidth(value)
            eraserLocation = nil
        })
    }

    private var eraserWidthBinding: Binding<CGFloat> {
        Binding(get: { controller.eraserWidth }, set: { value in
            controller.selectEraserWidth(value)
            eraserLocation = nil
        })
    }

    private var eraserCursorDiameter: CGFloat { controller.eraserWidth }

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
    let color: UIColor
    let width: CGFloat
    let eraser: Bool
    let eraserWidth: CGFloat
    let fingerDrawingEnabled: Bool
    let scrollEnabled: Bool
    @Binding var eraserLocation: CGPoint?
    @Binding var action: PencilAction?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = InteractivePencilCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = fingerDrawingEnabled ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = true
        if #available(iOS 18.0, *) { canvas.isDrawingEnabled = true }
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.contentInsetAdjustmentBehavior = .never
        canvas.minimumZoomScale = scrollEnabled ? 0.5 : 1
        canvas.maximumZoomScale = scrollEnabled ? 3 : 1
        canvas.bouncesZoom = true
        canvas.isScrollEnabled = true
        canvas.alwaysBounceHorizontal = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled

        let eraserTracker = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.trackEraser(_:))
        )
        eraserTracker.minimumPressDuration = 0
        eraserTracker.allowableMovement = .greatestFiniteMagnitude
        eraserTracker.cancelsTouchesInView = false
        eraserTracker.delegate = context.coordinator
        eraserTracker.isEnabled = eraser
        canvas.addGestureRecognizer(eraserTracker)
        context.coordinator.eraserTracker = eraserTracker

        if let data = Data(base64Encoded: encodedData),
           let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
        }
        context.coordinator.lastEncoded = encodedData
        updateTool(canvas)
        return canvas
    }

    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        updateTool(canvas)
        canvas.drawingPolicy = fingerDrawingEnabled ? .anyInput : .pencilOnly
        canvas.isUserInteractionEnabled = true
        if #available(iOS 18.0, *) { canvas.isDrawingEnabled = true }
        canvas.isScrollEnabled = true
        canvas.minimumZoomScale = scrollEnabled ? 0.5 : 1
        canvas.maximumZoomScale = scrollEnabled ? 3 : 1
        canvas.alwaysBounceHorizontal = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled
        context.coordinator.eraserTracker?.isEnabled = eraser
        if canvas.window != nil, !canvas.isFirstResponder {
            DispatchQueue.main.async { canvas.becomeFirstResponder() }
        }
        if let action, context.coordinator.lastActionID != action.id {
            context.coordinator.lastActionID = action.id
            switch action.kind {
            case .undo:
                canvas.undoManager?.undo()
                context.coordinator.publish(canvas)
            case .redo:
                canvas.undoManager?.redo()
                context.coordinator.publish(canvas)
            case .clear:
                let previousDrawing = canvas.drawing
                canvas.undoManager?.registerUndo(withTarget: context.coordinator) { coordinator in
                    coordinator.restore(previousDrawing, on: canvas)
                }
                canvas.undoManager?.setActionName("清空涂鸦")
                canvas.drawing = PKDrawing()
                context.coordinator.publish(canvas)
            }
            DispatchQueue.main.async { self.action = nil }
        }
        if context.coordinator.lastEncoded != encodedData,
           !canvas.isFirstResponder,
           let data = Data(base64Encoded: encodedData),
           let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing
            context.coordinator.lastEncoded = encodedData
        }
    }

    private func updateTool(_ canvas: PKCanvasView) {
        canvas.tool = eraser
            ? PKEraserTool(.bitmap, width: eraserWidth)
            : PKInkingTool(.pen, color: color, width: width)
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate, UIGestureRecognizerDelegate {
        var parent: PencilCanvasRepresentable
        var lastEncoded = ""
        var lastActionID: UUID?
        var drawingChanged = false
        weak var eraserTracker: UILongPressGestureRecognizer?

        init(parent: PencilCanvasRepresentable) { self.parent = parent }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingChanged = true
        }

        func canvasViewDidEndUsingTool(_ canvasView: PKCanvasView) {
            guard drawingChanged else { return }
            drawingChanged = false
            publish(canvasView)
        }

        @objc func trackEraser(_ recognizer: UILongPressGestureRecognizer) {
            guard parent.eraser else {
                parent.eraserLocation = nil
                return
            }
            switch recognizer.state {
            case .began, .changed:
                parent.eraserLocation = recognizer.location(in: recognizer.view)
            default:
                parent.eraserLocation = nil
            }
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        func publish(_ canvas: PKCanvasView) {
            let value = canvas.drawing.dataRepresentation().base64EncodedString()
            lastEncoded = value
            parent.encodedData = value
            drawingChanged = false
        }

        func restore(_ drawing: PKDrawing, on canvas: PKCanvasView) {
            canvas.drawing = drawing
            publish(canvas)
        }
    }
}

private final class InteractivePencilCanvasView: PKCanvasView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        isUserInteractionEnabled = true
        if #available(iOS 18.0, *) { isDrawingEnabled = true }
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
