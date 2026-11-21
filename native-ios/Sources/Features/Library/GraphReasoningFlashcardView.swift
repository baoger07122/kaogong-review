import SwiftData
import SwiftUI
import UIKit

private struct GraphFlashcardLoadedDrawing {
    let payloadKey: LibraryDetailPayloadKey
    let data: String
}

struct GraphReasoningFlashcardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let records: [LibraryRecordSnapshot]
    let onDoodleSaveError: (String) -> Void
    @StateObject private var doodleSession = LibraryDoodleSession()
    @State private var selectedRecordID: String?
    @State private var showsBack = false
    @State private var previewImage: GraphImagePreviewItem?
    @State private var loadedDrawing: GraphFlashcardLoadedDrawing?

    private var index: Int {
        records.firstIndex { $0.id == selectedRecordID } ?? 0
    }

    private var current: LibraryRecordSnapshot? {
        records.indices.contains(index) ? records[index] : nil
    }

    private var currentPayloadKey: LibraryDetailPayloadKey? {
        current.map { LibraryDetailPayloadKey(record: $0.record) }
    }

    private var currentCanvasID: String? {
        current.map { canvasID(for: $0) }
    }

    private var canFlip: Bool {
        !doodleSession.isPresented && !doodleSession.isDismissing
    }

    var body: some View {
        if let current {
            VStack(spacing: 14) {
                HStack {
                    Text("图形推理闪卡").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Text("\(index + 1) / \(records.count)")
                        .font(AppTheme.auxiliaryFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                card(current)
                controls(current)
            }
            .task(id: currentPayloadKey) { await loadDrawing(for: current) }
            .onChange(of: current.id, initial: true) { _, recordID in
                selectedRecordID = recordID
                showsBack = false
            }
            .onChange(of: currentCanvasID) { _, newCanvasID in
                if doodleSession.isPresented, doodleSession.targetRecordID != newCanvasID {
                    finishDoodle(leaving: true)
                }
            }
            .onDisappear {
                if doodleSession.isPresented, !doodleSession.isDismissing {
                    finishDoodle(leaving: true)
                }
            }
            .fullScreenCover(item: $previewImage) { item in
                GraphImagePreviewView(value: item.value)
            }
        }
    }

    private func card(_ snapshot: LibraryRecordSnapshot) -> some View {
        ZStack {
            if showsBack { back(snapshot) } else { front(snapshot) }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(18)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : (showsBack ? 360 : 0)), axis: (x: 0, y: 1, z: 0))
        .contentShape(Rectangle())
        .gesture(TapGesture().onEnded { flip() }, including: canFlip ? .all : .subviews)
        .accessibilityHint(canFlip ? "轻点查看\(showsBack ? "正面" : "答案与解析")" : "")
    }

    private func controls(_ snapshot: LibraryRecordSnapshot) -> some View {
        HStack(spacing: 12) {
            Button { move(-1) } label: { Label("上一张", systemImage: "chevron.left") }
                .buttonStyle(NativeSecondaryButtonStyle())
                .disabled(index == 0 || doodleSession.isDismissing)

            Button {
                if doodleSession.isPresented { finishDoodle() } else { openDoodle(snapshot) }
            } label: {
                Label(
                    doodleSession.isPresented ? "完成涂鸦" : "涂鸦",
                    systemImage: doodleSession.isPresented ? "pencil" : "pencil.and.scribble"
                )
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            }
            .buttonStyle(NativeSecondaryButtonStyle())
            .disabled(doodleSession.isDismissing || (!doodleSession.isPresented
                && (snapshot.imageValues.isEmpty || loadedDrawing?.payloadKey != currentPayloadKey)))
            .accessibilityIdentifier("graph-flashcard-doodle-toggle")

            Button { move(1) } label: {
                HStack(spacing: 5) {
                    Text("下一张")
                    Image(systemName: "chevron.right").accessibilityHidden(true)
                }
            }
            .buttonStyle(NativeSecondaryButtonStyle())
            .disabled(index == records.count - 1 || doodleSession.isDismissing)
        }
    }

    private func front(_ snapshot: LibraryRecordSnapshot) -> some View {
        let target = canvasID(for: snapshot)
        let isDrawing = doodleSession.isPresented && doodleSession.targetRecordID == target
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("正面")
                    .font(AppTheme.auxiliaryFont.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize()
                Spacer(minLength: 0)
                if isDrawing {
                    NativePencilDrawingToolbar(
                        controller: doodleSession.canvas.controller,
                        toolsEnabled: doodleSession.isCanvasActivationReady,
                        isClosing: doodleSession.isDismissing,
                        closeIdentifier: "graph-flashcard-doodle-close",
                        onClose: { finishDoodle() }
                    ) { EmptyView() }
                } else {
                    Text("轻点翻面")
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 44)

            Text(snapshot.title)
                .font(AppTheme.bodyFont)
                .fixedSize(horizontal: false, vertical: true)

            if !snapshot.imageValues.isEmpty {
                GraphFlashcardDiagram(
                    snapshot: snapshot,
                    session: doodleSession,
                    canvasID: target,
                    isDrawing: isDrawing,
                    savedDrawing: displayedDrawing(for: snapshot),
                    onPreview: { previewImage = GraphImagePreviewItem(value: $0) }
                )
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func back(_ snapshot: LibraryRecordSnapshot) -> some View {
        let object = snapshot.record.jsonObject ?? [:]
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("背面").font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent); Spacer(); Text("轻点翻回").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                answerRow("正确答案", value: text(object, "correctOption"), color: AppTheme.success)
                answerRow("我的答案", value: text(object, "userOption"), color: AppTheme.danger)
                detail("考点", text(object, "knowledgePoint"))
                detail("图形规律", text(object, "graphRule", fallback: "patternRule"))
                detail("识别思路", text(object, "recognition", fallback: "recognitionPath"))
                detail("错因", text(object, "errorCause"))
                detail("复盘笔记", text(object, "note"))
                detail("题目来源", text(object, "questionSource"))
                HStack {
                    Text(text(object, "status").isEmpty ? "未掌握" : text(object, "status"))
                        .font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.warning)
                    Spacer()
                    if let date = snapshot.createdAt { Text(date, format: .dateTime.year().month().day()).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                }
            }
        }
        .frame(height: 330)
    }

    private func answerRow(_ title: String, value: String, color: Color) -> some View {
        HStack { Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary); Spacer(); Text(value.isEmpty ? "未填写" : value).font(AppTheme.bodyFont.weight(.semibold)).foregroundStyle(color) }
            .padding(10).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func detail(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                Text(plainText(value)).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func flip() {
        guard canFlip else { return }
        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.42, bounce: 0.16)) {
            showsBack.toggle()
        }
    }

    private func move(_ offset: Int) {
        let nextIndex = index + offset
        guard records.indices.contains(nextIndex), !doodleSession.isDismissing else { return }
        let nextID = records[nextIndex].id
        let selectNext = {
            showsBack = false
            selectedRecordID = nextID
        }
        if doodleSession.isPresented {
            finishDoodle(onSaved: selectNext)
        } else {
            selectNext()
        }
    }

    private func diagramKey(for snapshot: LibraryRecordSnapshot) -> String {
        "v1|" + snapshot.imageIdentities.joined(separator: "|")
    }

    private func canvasID(for snapshot: LibraryRecordSnapshot) -> String {
        "\(snapshot.id)|\(diagramKey(for: snapshot))"
    }

    @MainActor
    private func loadDrawing(for snapshot: LibraryRecordSnapshot) async {
        guard !snapshot.imageValues.isEmpty else { return }
        let request = LibraryDetailPayloadKey(record: snapshot.record)
        let decoded = await LibraryPayloadDecodeCoordinator.shared.decode(
            key: request.decodeKey, payload: snapshot.record.payload, priority: .userInitiated
        )
        guard !Task.isCancelled, request == currentPayloadKey, let decoded else { return }
        let drawings = decoded.object[LibraryDoodlePersistence.flashcardDrawingsKey] as? [String: String]
        loadedDrawing = GraphFlashcardLoadedDrawing(payloadKey: request, data: drawings?[diagramKey(for: snapshot)] ?? "")
    }

    private func displayedDrawing(for snapshot: LibraryRecordSnapshot) -> String {
        if doodleSession.isDismissing, doodleSession.targetRecordID == canvasID(for: snapshot) {
            return doodleSession.canvas.drawingData
        }
        guard loadedDrawing?.payloadKey == LibraryDetailPayloadKey(record: snapshot.record) else { return "" }
        return loadedDrawing?.data ?? ""
    }

    private func openDoodle(_ snapshot: LibraryRecordSnapshot) {
        guard !snapshot.imageValues.isEmpty, let loadedDrawing,
              loadedDrawing.payloadKey == LibraryDetailPayloadKey(record: snapshot.record) else { return }
        let record = snapshot.record
        let context = modelContext
        let diagram = diagramKey(for: snapshot)
        showsBack = false
        doodleSession.present(
            targetRecordID: canvasID(for: snapshot),
            drawingData: loadedDrawing.data,
            legacyPreviewDataURL: "",
            source: "graph-flashcard",
            onSave: { data, _, _, _ in
                await LibraryDoodlePersistence.saveFlashcardDrawing(
                    record: record, context: context, diagramKey: diagram, drawingData: data
                )
            }
        )
    }

    private func finishDoodle(leaving: Bool = false, onSaved: (() -> Void)? = nil) {
        let session = doodleSession
        let reportError = onDoodleSaveError
        session.dismiss(reopenOnSaveFailure: !leaving) { [session] error in
            if let error {
                reportError(error)
            } else {
                onSaved?()
            }
            // Keep pending canvas serialization and the save alive if the flashcard view leaves.
            withExtendedLifetime(session) {}
        }
    }

    private func text(_ object: [String: Any], _ key: String, fallback: String? = nil) -> String {
        (object[key] as? String) ?? fallback.flatMap { object[$0] as? String } ?? ""
    }
    private func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GraphFlashcardDiagram: View {
    let snapshot: LibraryRecordSnapshot
    @ObservedObject var session: LibraryDoodleSession
    let canvasID: String
    let isDrawing: Bool
    let savedDrawing: String
    let onPreview: (String) -> Void

    private let width: CGFloat = 400
    private let rowHeight: CGFloat = 196
    private let spacing: CGFloat = 8

    var body: some View {
        let count = CGFloat(snapshot.imageValues.count)
        let height = rowHeight * count + spacing * (count - 1)
        GeometryReader { proxy in
            // Scale the image and PencilKit together so strokes retain their image coordinates.
            let scale = proxy.size.width / width
            ZStack {
                VStack(spacing: spacing) {
                    ForEach(Array(snapshot.imageValues.enumerated()), id: \.offset) { index, value in
                        Button { onPreview(value) } label: {
                            GraphFlashImage(value: value, cacheKey: snapshot.imageIdentities[index])
                                .frame(width: width, height: rowHeight)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("全屏查看题目图片")
                    }
                }
                .allowsHitTesting(!isDrawing)
                .accessibilityHidden(isDrawing)

                if isDrawing {
                    LibraryDoodleContentLayer(session: session, targetRecordID: canvasID, minimumCanvasHeight: 0)
                        .allowsHitTesting(!session.isDismissing)
                } else if !savedDrawing.isEmpty {
                    NativePencilDrawingPreview(encodedData: savedDrawing)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: width, height: height)
            .scaleEffect(scale, anchor: .topLeading)
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            .clipped()
        }
        .aspectRatio(width / height, contentMode: .fit)
        .frame(maxWidth: width)
        .overlay(alignment: .bottom) {
            if isDrawing {
                GraphFlashcardDrawingSettings(controller: session.canvas.controller)
            }
        }
        .id(canvasID)
    }
}

private struct GraphFlashcardDrawingSettings: View {
    @ObservedObject var controller: PencilDrawingController

    var body: some View {
        if let error = controller.canvasLoadError {
            Text(error)
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(AppTheme.danger)
                .padding(8)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .allowsHitTesting(false)
        } else if controller.showSettings {
            NativePencilDrawingSettingsPanel(controller: controller, includesSafeAreaBottomPadding: false)
        }
    }
}

private struct GraphFlashImage: View {
    let value: String
    let cacheKey: String
    @State private var localImage: UIImage?
    @State private var didFail = false
    private let maximumPixelSize = 1_200

    private var remoteURL: URL? {
        guard let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }

    var body: some View {
        Group {
            if let remoteURL {
                AsyncImage(url: remoteURL) { phase in
                    if let image = phase.image { image.resizable().scaledToFit() }
                    else if phase.error != nil { unavailable }
                    else { ProgressView() }
                }
            } else if let localImage {
                Image(uiImage: localImage).resizable().scaledToFit()
            } else if didFail {
                unavailable
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: cacheKey) {
            guard remoteURL == nil else { return }
            let image = await LibraryImageLoader.image(from: value, cacheKey: cacheKey, maximumPixelSize: maximumPixelSize)
            guard !Task.isCancelled else { return }
            localImage = image
            didFail = image == nil
        }
    }

    private var unavailable: some View {
        Image(systemName: "photo.badge.exclamationmark")
            .font(.system(size: 24))
            .foregroundStyle(.secondary)
            .accessibilityLabel("图片无法加载")
    }
}

private struct GraphImagePreviewItem: Identifiable {
    let id = UUID()
    let value: String
}

private struct GraphImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let value: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            image
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = min(6, max(1, lastScale * value.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 { reset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.25, bounce: 0.05)) {
                        if scale > 1 { reset() } else { scale = 2; lastScale = 2 }
                    }
                }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    @ViewBuilder private var image: some View {
        if let image = localImage {
            Image(uiImage: image).resizable().scaledToFit().padding(24)
        } else if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit().padding(24) }
                else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.white) }
                else { ProgressView().tint(.white) }
            }
        } else {
            Image(systemName: "photo.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.white)
        }
    }

    private var localImage: UIImage? {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...])).flatMap(UIImage.init(data:))
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
    }
}
