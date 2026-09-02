import PencilKit
import SwiftUI
import UIKit

private enum PencilActionKind { case undo, redo, clear, resetViewport }
private struct PencilAction { let id = UUID(); let kind: PencilActionKind }

struct NativePencilDrawingEditor: View {
    @Binding var encodedData: String
    var legacyPreviewDataURL = ""
    var transparentBackground = false
    var toolbarAtTop = false
    var onClose: (() -> Void)?
    @State private var color = UIColor.black
    @State private var width: CGFloat = 4
    @State private var eraser = false
    @State private var previousPenColor = UIColor.black
    @State private var previousPenWidth: CGFloat = 4
    @State private var action: PencilAction?
    @State private var showClearConfirmation = false

    var body: some View {
        Group {
            if #available(iOS 17.5, *) {
                editorContent
                    .onPencilSqueeze { phase in
                        if case .ended(_) = phase { toggleEraser() }
                    }
            } else {
                editorContent
            }
        }
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            if toolbarAtTop {
                toolStrip
                Divider()
            }
            canvas
            if legacyImage != nil {
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
        .clipShape(RoundedRectangle(cornerRadius: transparentBackground ? 0 : AppTheme.controlRadius))
        .overlay {
            if !transparentBackground {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
            }
        }
        .overlay {
            if showClearConfirmation {
                NativeDeleteDialog(
                    title: "清空涂鸦",
                    message: "确定清空当前全部笔迹？保存后将无法恢复。",
                    onDelete: {
                        action = PencilAction(kind: .clear)
                        showClearConfirmation = false
                    },
                    onCancel: { showClearConfirmation = false }
                )
            }
        }
    }

    private var canvas: some View {
        ZStack {
            (transparentBackground ? Color.clear : Color.white)
                .contentShape(Rectangle())
            if let legacyImage {
                Image(uiImage: legacyImage)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .accessibilityLabel("Web 旧涂鸦底图")
            }
            PencilCanvasRepresentable(
                encodedData: $encodedData,
                color: color,
                width: width,
                eraser: eraser,
                scrollEnabled: !transparentBackground,
                action: $action
            )
            .contentShape(Rectangle())
            .allowsHitTesting(true)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(minHeight: 260)
    }

    private var toolStrip: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                ForEach([UIColor.black, .systemRed, .systemBlue, .systemGreen], id: \.description) { value in
                    Button { selectPen(color: value) } label: {
                        Circle().fill(Color(uiColor: value)).frame(width: 23, height: 23)
                            .overlay(Circle().stroke(!eraser && color == value ? AppTheme.accent : .clear, lineWidth: 2.5).padding(-3))
                    }.buttonStyle(.plain)
                }
                Picker("粗细", selection: penWidthBinding) {
                    Text("细").tag(CGFloat(2)); Text("中").tag(CGFloat(4)); Text("粗").tag(CGFloat(8))
                }.pickerStyle(.segmented).frame(width: 120)
                }
            }
            Spacer(minLength: 4)
            if let onClose { toolButton("xmark", active: false, action: onClose) }
            toolButton(eraser ? "eraser.fill" : "eraser", active: eraser) { toggleEraser() }
            toolButton("arrow.uturn.backward", active: false) { action = PencilAction(kind: .undo) }
            toolButton("trash", active: false) { showClearConfirmation = true }
            toolButton("scope", active: false) { action = PencilAction(kind: .resetViewport) }
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
        Binding(get: { width }, set: { value in width = value; previousPenWidth = value; eraser = false })
    }

    private func selectPen(color value: UIColor) {
        color = value
        previousPenColor = value
        previousPenWidth = width
        eraser = false
    }

    private func toggleEraser() {
        if eraser {
            color = previousPenColor
            width = previousPenWidth
            eraser = false
        } else {
            previousPenColor = color
            previousPenWidth = width
            eraser = true
        }
    }

    private func toolButton(_ image: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? Color.white : Color.primary)
                .frame(width: 36, height: 34)
                .background(active ? AppTheme.accent : Color.primary.opacity(0.07), in: Circle())
        }
        .buttonStyle(.plain)
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var encodedData: String
    let color: UIColor
    let width: CGFloat
    let eraser: Bool
    let scrollEnabled: Bool
    @Binding var action: PencilAction?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = InteractivePencilCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
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
        if let data = Data(base64Encoded: encodedData), let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
        context.coordinator.lastEncoded = encodedData
        updateTool(canvas)
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        context.coordinator.parent = self
        updateTool(canvas)
        canvas.drawingPolicy = .anyInput
        canvas.isUserInteractionEnabled = true
        if #available(iOS 18.0, *) { canvas.isDrawingEnabled = true }
        canvas.isScrollEnabled = true
        canvas.minimumZoomScale = scrollEnabled ? 0.5 : 1
        canvas.maximumZoomScale = scrollEnabled ? 3 : 1
        canvas.alwaysBounceHorizontal = scrollEnabled
        canvas.alwaysBounceVertical = scrollEnabled
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
            case .clear: canvas.drawing = PKDrawing(); context.coordinator.publish(canvas)
            case .resetViewport:
                canvas.setZoomScale(1, animated: true)
                canvas.setContentOffset(.zero, animated: true)
            }
            DispatchQueue.main.async { self.action = nil }
        }
        if context.coordinator.lastEncoded != encodedData, !canvas.isFirstResponder,
           let data = Data(base64Encoded: encodedData), let drawing = try? PKDrawing(data: data) {
            canvas.drawing = drawing; context.coordinator.lastEncoded = encodedData
        }
    }
    private func updateTool(_ canvas: PKCanvasView) { canvas.tool = eraser ? PKEraserTool(.vector) : PKInkingTool(.pen, color: color, width: width) }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasRepresentable
        var lastEncoded = ""
        var lastActionID: UUID?
        init(parent: PencilCanvasRepresentable) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            publish(canvasView)
        }
        func publish(_ canvas: PKCanvasView) { let value = canvas.drawing.dataRepresentation().base64EncodedString(); lastEncoded = value; parent.encodedData = value }
    }
}

private final class InteractivePencilCanvasView: PKCanvasView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard window != nil else { return }
        isUserInteractionEnabled = true
        drawingPolicy = .anyInput
        if #available(iOS 18.0, *) { isDrawingEnabled = true }
        DispatchQueue.main.async { [weak self] in self?.becomeFirstResponder() }
    }
}

enum PencilDrawingCompatibility {
    static func previewDataURL(encodedData: String) -> String {
        guard let data = Data(base64Encoded: encodedData), let drawing = try? PKDrawing(data: data), !drawing.bounds.isEmpty else { return "" }
        let bounds = drawing.bounds.insetBy(dx: -18, dy: -18)
        let image = drawing.image(from: bounds, scale: 2)
        guard let png = image.pngData() else { return "" }
        return "data:image/png;base64,\(png.base64EncodedString())"
    }
}
