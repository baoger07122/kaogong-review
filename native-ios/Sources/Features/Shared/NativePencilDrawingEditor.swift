import PencilKit
import SwiftUI
import UIKit

private enum PencilActionKind { case undo, redo, clear, resetViewport }
private struct PencilAction { let id = UUID(); let kind: PencilActionKind }

struct NativePencilDrawingEditor: View {
    @Binding var encodedData: String
    var legacyPreviewDataURL = ""
    @State private var color = UIColor.black
    @State private var width: CGFloat = 4
    @State private var eraser = false
    @State private var action: PencilAction?
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.white
                if let legacyImage {
                    Image(uiImage: legacyImage)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .accessibilityLabel("Web 旧涂鸦底图")
                }
                PencilCanvasRepresentable(encodedData: $encodedData, color: color, width: width, eraser: eraser, action: $action)
            }
            .frame(minHeight: 260)
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
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach([UIColor.black, .systemRed, .systemBlue, .systemGreen], id: \.description) { value in
                        Button { color = value; eraser = false } label: {
                            Circle().fill(Color(uiColor: value)).frame(width: 23, height: 23)
                                .overlay(Circle().stroke(!eraser && color == value ? AppTheme.accent : .clear, lineWidth: 2.5).padding(-3))
                        }.buttonStyle(.plain)
                    }
                    Picker("粗细", selection: $width) {
                        Text("细").tag(CGFloat(2)); Text("中").tag(CGFloat(4)); Text("粗").tag(CGFloat(8))
                    }.pickerStyle(.segmented).frame(width: 120)
                    toolButton(eraser ? "eraser.fill" : "eraser") { eraser.toggle() }
                    toolButton("arrow.uturn.backward") { action = PencilAction(kind: .undo) }
                    toolButton("arrow.uturn.forward") { action = PencilAction(kind: .redo) }
                    toolButton("scope") { action = PencilAction(kind: .resetViewport) }
                    toolButton("trash") { showClearConfirmation = true }
                }.padding(8)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.controlRadius))
        .overlay(RoundedRectangle(cornerRadius: AppTheme.controlRadius).stroke(Color.primary.opacity(0.08), lineWidth: 0.7))
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

    private var legacyImage: UIImage? {
        guard let marker = legacyPreviewDataURL.range(of: "base64,") else { return nil }
        let encoded = String(legacyPreviewDataURL[marker.upperBound...])
        guard let data = Data(base64Encoded: encoded) else { return nil }
        return UIImage(data: data)
    }

    private func toolButton(_ image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 13, weight: .semibold)).frame(width: 32, height: 29).background(Color.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(.plain)
    }
}

private struct PencilCanvasRepresentable: UIViewRepresentable {
    @Binding var encodedData: String
    let color: UIColor
    let width: CGFloat
    let eraser: Bool
    @Binding var action: PencilAction?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIView(context: Context) -> PKCanvasView {
        let canvas = PKCanvasView()
        canvas.delegate = context.coordinator
        canvas.drawingPolicy = .anyInput
        canvas.backgroundColor = .clear
        canvas.isOpaque = false
        canvas.minimumZoomScale = 0.5
        canvas.maximumZoomScale = 3
        canvas.bouncesZoom = true
        canvas.alwaysBounceHorizontal = true
        canvas.alwaysBounceVertical = true
        if let data = Data(base64Encoded: encodedData), let drawing = try? PKDrawing(data: data) { canvas.drawing = drawing }
        context.coordinator.lastEncoded = encodedData
        updateTool(canvas)
        updateViewport(canvas)
        return canvas
    }
    func updateUIView(_ canvas: PKCanvasView, context: Context) {
        updateTool(canvas)
        updateViewport(canvas)
        if let action, context.coordinator.lastActionID != action.id {
            context.coordinator.lastActionID = action.id
            switch action.kind {
            case .undo: canvas.undoManager?.undo()
            case .redo: canvas.undoManager?.redo()
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
    fileprivate func updateViewport(_ canvas: PKCanvasView) {
        let drawingBounds = canvas.drawing.bounds
        let width = max(max(canvas.bounds.width, drawingBounds.maxX + 120), 1_200)
        let height = max(max(canvas.bounds.height, drawingBounds.maxY + 120), 900)
        let target = CGSize(width: width, height: height)
        if canvas.contentSize != target { canvas.contentSize = target }
    }

    final class Coordinator: NSObject, PKCanvasViewDelegate {
        var parent: PencilCanvasRepresentable
        var lastEncoded = ""
        var lastActionID: UUID?
        init(parent: PencilCanvasRepresentable) { self.parent = parent }
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            parent.updateViewport(canvasView)
            publish(canvasView)
        }
        func publish(_ canvas: PKCanvasView) { let value = canvas.drawing.dataRepresentation().base64EncodedString(); lastEncoded = value; parent.encodedData = value }
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
