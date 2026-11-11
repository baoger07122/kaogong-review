import SwiftUI
import UIKit

enum LibraryDoodlePane: String, CaseIterable, Hashable {
    case material
    case question
}

enum LibraryDoodleLayoutDirection: String, CaseIterable, Hashable {
    case horizontal
    case vertical
}

@MainActor
private final class LibraryOneShotDisplayLink: NSObject {
    private var displayLink: CADisplayLink?
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
    }

    func schedule() {
        let link = CADisplayLink(target: self, selector: #selector(didDisplayFrame(_:)))
        displayLink = link
        link.add(to: .main, forMode: .common)
    }

    func cancel() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func didDisplayFrame(_ link: CADisplayLink) {
        link.invalidate()
        displayLink = nil
        action()
    }
}

@MainActor
final class LibraryDoodleSession: ObservableObject {
    @Published var isPresented = false
    @Published private(set) var isCanvasActivationReady = false
    @Published var saveError: String?
    @Published private(set) var isLoadingDrawing = false
    @Published private(set) var targetRecordID: String?
    @Published private(set) var presentationSource = "unknown"
    @Published private(set) var activeSplitDrawingPane: LibraryDoodlePane?
    @Published private(set) var splitDrawingValues: [String: String] = [:]
    @Published private(set) var splitDrawingRecordID: String?
    @Published private(set) var splitDrawingLayoutDirection: LibraryDoodleLayoutDirection = .vertical
    @Published private(set) var hasPendingSplitDrawingChanges = false
    let canvas = LibraryDoodleCanvasState()
    private var saveHandler: ((String, Bool, Int, Int) async -> String?)?
    private var isDismissing = false
    private var splitDrawingBaseline: [String: String] = [:]
    private var drawingLoadFailed = false
    private var drawingLoadDataReceived = false
    private(set) var presentationGeneration = 0
    private var drawingLoadTask: Task<Void, Never>?
    private var drawingRevisionAtPresentation = 0
    private var presentationStartedAt: TimeInterval?
    private var didLogCanvasFrame = false
    private var didLogCanvasInteractive = false
    private var pendingFirstFrameCallback: LibraryOneShotDisplayLink?
    private var pendingToolbarFrameCallback: LibraryOneShotDisplayLink?
    private var onFirstCanvasFrame: (() -> Void)?
    private var pendingCanvasActivation: (recordID: String, generation: Int, drawingData: String, legacyPreviewDataURL: String, hostID: String?, reuseLoadedCanvas: Bool)?
    private(set) var mountedCanvasHostID: String?

    var userDrawingRevision: Int { canvas.controller.userDrawingRevision }

    var hasUnsavedDrawingChanges: Bool {
        canvas.controller.userDrawingRevision > drawingRevisionAtPresentation
            || canvas.controller.legacyPreviewCleared
            || hasPendingSplitDrawingChanges
    }

    var isSplitDrawingSession: Bool {
        activeSplitDrawingPane != nil
    }

    func present(
        targetRecordID: String,
        drawingData: String,
        legacyPreviewDataURL: String,
        isLoadingDrawing: Bool = false,
        source: String,
        splitDrawingPane: LibraryDoodlePane? = nil,
        splitDrawingValues: [String: String] = [:],
        splitDrawingBaseline: [String: String] = [:],
        splitDrawingLayoutDirection: LibraryDoodleLayoutDirection = .vertical,
        interactionStartedAt: TimeInterval? = nil,
        onFirstCanvasFrame: (() -> Void)? = nil,
        deferCanvasActivation: Bool = false,
        canvasHostID: String? = nil,
        onSave: @escaping (String, Bool, Int, Int) async -> String?
    ) {
        guard !isPresented, !isDismissing else { return }
        let preparationStart = ProcessInfo.processInfo.systemUptime
        let interactionStart = interactionStartedAt ?? preparationStart
        let previouslyLoadedDrawingData = splitDrawingPane.map {
            self.splitDrawingValues[Self.splitDrawingStorageKey(
                pane: $0,
                layout: self.splitDrawingLayoutDirection
            )] ?? ""
        } ?? canvas.drawingData
        let canReuseLoadedCanvas = deferCanvasActivation
            && self.targetRecordID == targetRecordID
            && mountedCanvasHostID == canvasHostID
            && canvas.controller.canvasReady
            && !canvas.controller.hasPendingDrawingPublish
            && previouslyLoadedDrawingData == drawingData
            && canvas.legacyPreviewDataURL == legacyPreviewDataURL
        drawingLoadTask?.cancel()
        drawingLoadTask = nil
        presentationGeneration &+= 1
        saveError = nil
        isDismissing = false
        drawingLoadFailed = false
        drawingLoadDataReceived = false
        self.isLoadingDrawing = isLoadingDrawing
        presentationSource = source
        activeSplitDrawingPane = splitDrawingPane
        if splitDrawingPane != nil {
            let keepPendingValues = hasPendingSplitDrawingChanges && splitDrawingRecordID == targetRecordID
            if !keepPendingValues {
                self.splitDrawingValues = splitDrawingValues
                self.splitDrawingBaseline = splitDrawingBaseline.isEmpty ? splitDrawingValues : splitDrawingBaseline
            }
            self.splitDrawingRecordID = targetRecordID
            self.splitDrawingLayoutDirection = splitDrawingLayoutDirection
            hasPendingSplitDrawingChanges = !pendingSplitDrawingValues().isEmpty
        } else if !(hasPendingSplitDrawingChanges && splitDrawingRecordID == targetRecordID) {
            clearSplitDrawingSession()
        }
        presentationStartedAt = interactionStart
        didLogCanvasFrame = false
        didLogCanvasInteractive = false
        pendingFirstFrameCallback = nil
        self.onFirstCanvasFrame = onFirstCanvasFrame
        self.targetRecordID = targetRecordID
        canvas.canvasFrameInGlobal = nil
        canvas.canvasFrameOwnerID = nil
        if !canReuseLoadedCanvas {
            canvas.controller.canvasReady = false
            canvas.controller.canvasLoadError = nil
        }
        saveHandler = onSave
        if deferCanvasActivation {
            isCanvasActivationReady = false
            pendingCanvasActivation = (
                targetRecordID,
                presentationGeneration,
                drawingData,
                legacyPreviewDataURL,
                canvasHostID,
                canReuseLoadedCanvas
            )
        } else {
            canvas.drawingData = drawingData
            canvas.legacyPreviewDataURL = legacyPreviewDataURL
            canvas.controller.prepareForPresentation()
            drawingRevisionAtPresentation = canvas.controller.userDrawingRevision
            isCanvasActivationReady = true
            LibraryPerformanceLog.mark("doodle.present.prepare", since: preparationStart)
        }

        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = true }
        LibraryPerformanceLog.mark("doodle.overlay-state", since: interactionStart)
    }

    func noteToolbarMounted() {
        guard isPresented, let presentationStartedAt else { return }
        guard let pendingCanvasActivation else { return }
        let recordID = pendingCanvasActivation.recordID
        let generation = pendingCanvasActivation.generation
        LibraryPerformanceLog.mark("doodle.toolbar-mounted", since: presentationStartedAt)
        pendingToolbarFrameCallback?.cancel()
        let callback = LibraryOneShotDisplayLink { [weak self] in
            guard let self,
                  self.isPresented,
                  self.presentationGeneration == generation,
                  self.targetRecordID == recordID,
                  let startedAt = self.presentationStartedAt else { return }
            LibraryPerformanceLog.mark("doodle.tap-to-toolbar-first-frame", since: startedAt)
            self.pendingToolbarFrameCallback = nil
            self.activateDeferredCanvas(recordID: recordID, generation: generation)
        }
        pendingToolbarFrameCallback = callback
        callback.schedule()
    }

    func noteCanvasHostMounted(_ hostID: String) {
        mountedCanvasHostID = hostID
        LibraryPerformanceLog.event("doodle.canvas-host-mounted id=\(LibraryPerformanceLog.shortIdentifier(hostID))")
        if isPresented, isCanvasActivationReady, let presentationStartedAt {
            LibraryPerformanceLog.mark("doodle.tap-to-canvas-mounted", since: presentationStartedAt)
        }
    }

    func noteCanvasHostUnmounted(_ hostID: String) {
        guard mountedCanvasHostID == hostID else { return }
        mountedCanvasHostID = nil
    }

    func shouldMountCanvas(for recordID: String, hostID: String) -> Bool {
        targetRecordID == recordID && (isCanvasActivationReady || mountedCanvasHostID == hostID)
    }

    private func activateDeferredCanvas(recordID: String, generation: Int) {
        guard let pending = pendingCanvasActivation,
              pending.recordID == recordID,
              pending.generation == generation,
              isPresented,
              targetRecordID == recordID,
              presentationGeneration == generation else { return }
        let activationStart = ProcessInfo.processInfo.systemUptime
        let canReuse = pending.reuseLoadedCanvas
            && mountedCanvasHostID == pending.hostID
            && canvas.controller.canvasReady
            && !canvas.controller.hasPendingDrawingPublish
        canvas.controller.prepareForPresentation(
            preservingLoadedDrawing: canReuse,
            persistToolSelection: false
        )
        if !canReuse {
            canvas.drawingData = pending.drawingData
            canvas.legacyPreviewDataURL = pending.legacyPreviewDataURL
        }
        drawingRevisionAtPresentation = canvas.controller.userDrawingRevision
        pendingCanvasActivation = nil
        isCanvasActivationReady = true
        if let presentationStartedAt {
            LibraryPerformanceLog.mark("doodle.tap-to-canvas-activation", since: presentationStartedAt)
        }
        LibraryPerformanceLog.mark("doodle.canvas-prepare", since: activationStart)
        LibraryPerformanceLog.mark(canReuse ? "doodle.canvas-reuse-activation" : "doodle.canvas-activation", since: activationStart)
    }

    func requestSplitDrawingPane(_ pane: LibraryDoodlePane) {
        guard isPresented, !isDismissing, activeSplitDrawingPane != nil,
              activeSplitDrawingPane != pane else { return }
        let generation = presentationGeneration
        canvas.controller.commit { [weak self] in
            guard let self, self.isPresented,
                  self.presentationGeneration == generation,
                  self.activeSplitDrawingPane != nil else { return }
            self.canvas.canvasFrameInGlobal = nil
            self.canvas.canvasFrameOwnerID = nil
            self.activeSplitDrawingPane = pane
        }
    }

    func splitDrawingData(for pane: LibraryDoodlePane, layout: LibraryDoodleLayoutDirection) -> String {
        splitDrawingValues[Self.splitDrawingStorageKey(pane: pane, layout: layout)] ?? ""
    }

    func updateSplitDrawingData(
        _ drawingData: String,
        for pane: LibraryDoodlePane,
        layout: LibraryDoodleLayoutDirection
    ) {
        guard splitDrawingRecordID == targetRecordID else { return }
        let key = Self.splitDrawingStorageKey(pane: pane, layout: layout)
        guard splitDrawingValues[key] != drawingData else { return }
        var values = splitDrawingValues
        values[key] = drawingData
        splitDrawingValues = values
        hasPendingSplitDrawingChanges = !pendingSplitDrawingValues().isEmpty
        if isPresented, activeSplitDrawingPane == pane, splitDrawingLayoutDirection == layout {
            canvas.drawingData = drawingData
        }
    }

    func pendingSplitDrawingValues() -> [String: String] {
        Dictionary(uniqueKeysWithValues: splitDrawingValues.compactMap { key, value in
            splitDrawingBaseline[key] == value ? nil : (key, value)
        })
    }

    func splitDrawingBaselineValues() -> [String: String] {
        splitDrawingBaseline
    }

    func markSplitDrawingValuesSaved() {
        splitDrawingBaseline = splitDrawingValues
        hasPendingSplitDrawingChanges = false
    }

    static func splitDrawingStorageKey(
        pane: LibraryDoodlePane,
        layout: LibraryDoodleLayoutDirection
    ) -> String {
        "\(layout.rawValue).\(pane.rawValue)"
    }

    func commitCurrentDrawing(_ completion: @escaping () -> Void) {
        guard isPresented else { completion(); return }
        canvas.controller.commit(completion)
    }

    func completeDrawingLoad(_ drawingData: String) {
        guard isPresented, isLoadingDrawing else { return }
        drawingLoadTask = nil
        drawingLoadDataReceived = true
        canvas.controller.beginDrawingReload()
        canvas.drawingData = drawingData
        noteCanvasInteractive()
    }

    func failDrawingLoad(_ message: String) {
        guard isPresented, isLoadingDrawing else { return }
        drawingLoadTask = nil
        isLoadingDrawing = false
        drawingLoadFailed = true
        canvas.controller.canvasLoadError = message
    }

    func beginDrawingLoad(
        recordID: String,
        startedAt: TimeInterval,
        loader: @escaping () async throws -> String,
        onLoaded: @escaping (String) -> Void = { _ in }
    ) {
        guard isPresented, isLoadingDrawing, targetRecordID == recordID else { return }
        drawingLoadTask?.cancel()
        let generation = presentationGeneration
        drawingLoadTask = Task { @MainActor [weak self] in
            do {
                let drawing = try await loader()
                guard let self, !Task.isCancelled,
                      self.presentationGeneration == generation,
                      self.isPresented,
                      self.targetRecordID == recordID,
                      self.isLoadingDrawing else { return }
                LibraryPerformanceLog.mark("doodle.read.background-result", since: startedAt)
                onLoaded(drawing)
                self.completeDrawingLoad(drawing)
            } catch {
                guard let self, !Task.isCancelled,
                      self.presentationGeneration == generation,
                      self.isPresented,
                      self.targetRecordID == recordID,
                      self.isLoadingDrawing else { return }
                self.failDrawingLoad("涂鸦读取失败：\(error.localizedDescription)")
            }
        }
    }

    func dismiss() {
        dismiss(reopenOnSaveFailure: true, completion: nil)
    }

    func dismiss(
        reopenOnSaveFailure: Bool,
        completion: ((String?) -> Void)?
    ) {
        guard isPresented, !isDismissing else { completion?(nil); return }
        if pendingCanvasActivation != nil {
            pendingCanvasActivation = nil
            pendingToolbarFrameCallback?.cancel()
            pendingToolbarFrameCallback = nil
            saveHandler = nil
            finishDismissal()
            clearSplitDrawingSession()
            completion?(nil)
            return
        }
        if isLoadingDrawing {
            let closeStart = ProcessInfo.processInfo.systemUptime
            drawingLoadTask?.cancel()
            drawingLoadTask = nil
            saveHandler = nil
            finishDismissal()
            clearSplitDrawingSession()
            isDismissing = false
            LibraryPerformanceLog.mark("doodle.close-while-loading", since: closeStart)
            completion?(nil)
            return
        }
        if drawingLoadFailed {
            saveHandler = nil
            finishDismissal()
            clearSplitDrawingSession()
            completion?(nil)
            return
        }
        isDismissing = true
        saveError = nil
        let handler = saveHandler
        let dismissalGeneration = presentationGeneration
        let dismissalTargetRecordID = targetRecordID
        let dismissalLoadRevision = canvas.controller.drawingLoadRevision
        let closeStart = ProcessInfo.processInfo.systemUptime
        LibraryPerformanceLog.mark("doodle.close-tap", since: closeStart)
        let completeSnapshot: () -> Void = { [weak self] in
            guard let self,
                  self.isPresented,
                  self.presentationGeneration == dismissalGeneration,
                  self.targetRecordID == dismissalTargetRecordID else { return }
            guard self.canvas.controller.drawingLoadRevision == dismissalLoadRevision else {
                self.isDismissing = false
                completion?("涂鸦画布已切换，未能安全结束当前涂鸦。")
                return
            }
            let drawingData = self.canvas.drawingData
            let legacyPreviewCleared = self.canvas.controller.legacyPreviewCleared
            let drawingRevision = self.userDrawingRevision
            let hasChanges = self.hasUnsavedDrawingChanges
            LibraryPerformanceLog.mark("doodle.drawing-snapshot", since: closeStart)

            // The canvas can disappear as soon as the final snapshot exists. The
            // record save is deliberately scheduled after the state change so a
            // JSON/SwiftData write cannot block the visible close feedback.
            self.finishDismissal()
            LibraryPerformanceLog.mark("doodle.overlay-hidden", since: closeStart)

            guard hasChanges else {
                self.saveHandler = nil
                self.clearSplitDrawingSession(keepingLoadedCanvasValues: true)
                self.isDismissing = false
                LibraryPerformanceLog.mark("doodle.close-no-change", since: closeStart)
                completion?(nil)
                return
            }

            Task { @MainActor [weak self] in
                guard let self,
                      self.presentationGeneration == dismissalGeneration,
                      self.targetRecordID == dismissalTargetRecordID else { return }
                let saveStart = ProcessInfo.processInfo.systemUptime
                if let error = await handler?(drawingData, legacyPreviewCleared, dismissalGeneration, drawingRevision) {
                    self.saveError = error
                    self.isDismissing = false
                    if reopenOnSaveFailure {
                        self.saveHandler = handler
                        self.isPresented = true
                    } else {
                        self.saveHandler = nil
                        self.clearSplitDrawingSession(keepingPendingValues: true)
                    }
                    completion?(error)
                    return
                }
                LibraryPerformanceLog.mark("doodle.save-handler", since: saveStart)
                self.saveHandler = nil
                self.clearSplitDrawingSession(keepingLoadedCanvasValues: true)
                self.isDismissing = false
                completion?(nil)
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

    private func clearSplitDrawingSession(
        keepingPendingValues: Bool = false,
        keepingLoadedCanvasValues: Bool = false
    ) {
        activeSplitDrawingPane = nil
        guard !keepingPendingValues || !hasPendingSplitDrawingChanges else { return }
        if keepingLoadedCanvasValues, splitDrawingRecordID == targetRecordID {
            hasPendingSplitDrawingChanges = false
            return
        }
        splitDrawingValues = [:]
        splitDrawingBaseline = [:]
        splitDrawingRecordID = nil
        splitDrawingLayoutDirection = .vertical
        hasPendingSplitDrawingChanges = false
    }

    func noteCanvasFramePreference() {
        guard isPresented, let presentationStartedAt else { return }
        if !didLogCanvasFrame {
            didLogCanvasFrame = true
            LibraryPerformanceLog.mark("doodle.canvas-frame-preference", since: presentationStartedAt)
            let generation = presentationGeneration
            let callback = LibraryOneShotDisplayLink { [weak self] in
                guard let self,
                      self.isPresented,
                      self.presentationGeneration == generation,
                      let presentationStartedAt = self.presentationStartedAt else { return }
                LibraryPerformanceLog.mark("doodle.canvas-first-frame", since: presentationStartedAt)
                let onFirstCanvasFrame = self.onFirstCanvasFrame
                self.onFirstCanvasFrame = nil
                self.pendingFirstFrameCallback = nil
                onFirstCanvasFrame?()
            }
            pendingFirstFrameCallback = callback
            callback.schedule()
        }
        noteCanvasInteractive()
    }

    func noteCanvasInteractive() {
        guard isPresented, isCanvasActivationReady, !didLogCanvasInteractive, canvas.controller.canvasReady,
              canvas.canvasFrameInGlobal != nil, let presentationStartedAt else { return }
        guard !isLoadingDrawing || drawingLoadDataReceived else { return }
        isLoadingDrawing = false
        didLogCanvasInteractive = true
        LibraryPerformanceLog.mark("doodle.tap-to-canvas-ready", since: presentationStartedAt)
        LibraryPerformanceLog.mark("doodle.canvas-interactive", since: presentationStartedAt)
    }

    private func finishDismissal() {
        pendingFirstFrameCallback = nil
        pendingToolbarFrameCallback?.cancel()
        pendingToolbarFrameCallback = nil
        pendingCanvasActivation = nil
        onFirstCanvasFrame = nil
        isCanvasActivationReady = false
        canvas.controller.showSettings = false
        canvas.canvasFrameInGlobal = nil
        canvas.canvasFrameOwnerID = nil
        isLoadingDrawing = false
        drawingLoadFailed = false
        drawingLoadDataReceived = false

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
    @Published var canvasFrameOwnerID: String?
    let controller = PencilDrawingController()
}

struct LibraryDoodleOverlay: View {
    @ObservedObject var session: LibraryDoodleSession
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    @ObservedObject private var controller: PencilDrawingController
    @State private var showsDelayedLoadingIndicator = false

    init(session: LibraryDoodleSession) {
        self.session = session
        _canvas = ObservedObject(wrappedValue: session.canvas)
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    var body: some View {
        GeometryReader { proxy in
            let activeCanvasFrame = session.isLoadingDrawing ? nil : canvasPassThroughRect(in: proxy)
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.18)
                    .contentShape(Rectangle())
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)

                // The transparent shield blocks underlying controls while the
                // canvas loads, then leaves only the active canvas target hittable.
                LibraryDoodleInteractionShield(
                    passThroughRect: activeCanvasFrame
                )
                .frame(width: proxy.size.width, height: proxy.size.height)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(interactionShieldLabel)
                .accessibilityValue("presented=\(session.isPresented)|\(activeCanvasFrame == nil ? "canvas-loading" : "canvas-ready")")
                .accessibilityIdentifier("library-doodle-interaction-shield")

                if let message = controller.canvasLoadError {
                    statusMessage(message)
                        .allowsHitTesting(false)
                } else if showsDelayedLoadingIndicator {
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

                if controller.showSettings {
                    let toolbarTop = max(proxy.safeAreaInsets.top + 5, 28)
                    let reservedTop = toolbarTop + 40 + 12
                    let availablePanelHeight = max(
                        0,
                        proxy.size.height - reservedTop - proxy.safeAreaInsets.bottom - 12
                    )
                    NativePencilDrawingSettingsPanel(
                        controller: controller,
                        includesSafeAreaBottomPadding: false
                    )
                        .transition(.opacity)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: availablePanelHeight, alignment: .bottom)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 12)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .zIndex(2)
                }

                if let saveError = session.saveError {
                    statusMessage(saveError)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, proxy.safeAreaInsets.bottom + 18)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .animation(.easeInOut(duration: 0.16), value: controller.showSettings)
        }
        .ignoresSafeArea()
        .allowsHitTesting(session.isPresented)
        .task(id: session.isPresented) {
            await updateDelayedLoadingIndicator(for: session.isPresented)
        }
        .onChange(of: controller.canvasReady) { _, _ in session.noteCanvasInteractive() }
        .onAppear { session.noteToolbarMounted() }
    }

    @MainActor
    private func updateDelayedLoadingIndicator(for isPresented: Bool) async {
        showsDelayedLoadingIndicator = false
        guard isPresented else { return }

        do {
            try await Task.sleep(nanoseconds: 180_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled,
              session.isPresented,
              session.isLoadingDrawing || !controller.canvasReady,
              controller.canvasLoadError == nil else { return }

        showsDelayedLoadingIndicator = true
        while session.isPresented,
              (session.isLoadingDrawing || !controller.canvasReady),
              controller.canvasLoadError == nil {
            do {
                try await Task.sleep(nanoseconds: 20_000_000)
            } catch {
                return
            }
        }
        guard !Task.isCancelled else { return }

        do {
            try await Task.sleep(nanoseconds: 160_000_000)
        } catch {
            return
        }
        guard !Task.isCancelled else { return }
        showsDelayedLoadingIndicator = false
    }

    private var toolbar: some View {
        NativeDoodleToolbarCapsule {
            toolbarButton("xmark", label: "退出涂鸦", action: { session.dismiss() })
                .accessibilityIdentifier("library-doodle-close")
            if session.isSplitDrawingSession {
                splitPaneButton(.material, title: "材料")
                splitPaneButton(.question, title: "题目")
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 2)
                    .accessibilityHidden(true)
            }
            toolbarButton(
                controller.eraser ? "pencil.tip.crop.circle" : "pencil.tip.crop.circle.fill",
                label: "画笔",
                active: !controller.eraser,
                disabled: !session.isCanvasActivationReady,
                action: { controller.selectPenTool() }
            )
            toolbarButton(
                controller.eraser ? "eraser.fill" : "eraser",
                label: "橡皮擦",
                active: controller.eraser,
                disabled: !session.isCanvasActivationReady,
                action: controller.selectEraserTool
            )
            toolbarButton("arrow.uturn.backward", label: "撤销", disabled: !session.isCanvasActivationReady, action: controller.undo)
            toolbarButton("trash", label: "清空涂鸦", disabled: !session.isCanvasActivationReady, action: controller.requestClear)
            toolbarButton(
                "paintpalette",
                label: controller.showSettings ? "收起画笔调节" : "展开画笔调节",
                active: controller.showSettings,
                disabled: !session.isCanvasActivationReady
            ) {
                controller.showSettings.toggle()
            }
            toolbarButton(
                "hand.draw",
                label: controller.fingerDrawingEnabled ? "关闭手指涂鸦" : "开启手指涂鸦",
                active: controller.fingerDrawingEnabled,
                disabled: !session.isCanvasActivationReady
            ) {
                controller.fingerDrawingEnabled.toggle()
            }
        }
    }

    private func splitPaneButton(_ pane: LibraryDoodlePane, title: String) -> some View {
        let isSelected = session.activeSplitDrawingPane == pane
        return Button {
            session.requestSplitDrawingPane(pane)
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                .foregroundStyle(isSelected ? AppTheme.accent : Color.secondary)
                .frame(minWidth: 30, minHeight: 30)
                .padding(.horizontal, 3)
                .background(isSelected ? AppTheme.accent.opacity(0.12) : .clear, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(LibraryDoodleToolbarButtonStyle())
        .disabled(!session.isCanvasActivationReady)
        .accessibilityLabel("涂鸦目标：\(title)")
        .accessibilityValue(isSelected ? "当前目标" : "未选择")
        .accessibilityIdentifier("library-doodle-target-\(pane.rawValue)")
    }

    private func toolbarButton(
        _ systemImage: String,
        label: String,
        active: Bool = false,
        disabled: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            let tapStart = ProcessInfo.processInfo.systemUptime
            action()
            LibraryPerformanceLog.mark("doodle.tool.tap-feedback", since: tapStart)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? AppTheme.accent : Color.primary)
                .frame(width: 32, height: 44)
                .background(active ? AppTheme.accent.opacity(0.12) : .clear, in: Circle())
                .overlay {
                    if active {
                        Circle()
                            .stroke(AppTheme.accent.opacity(0.35), lineWidth: 0.8)
                            .frame(width: 28, height: 28)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(LibraryDoodleToolbarButtonStyle())
        .disabled(disabled)
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
        guard session.isCanvasActivationReady,
              controller.canvasReady,
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

    private var interactionShieldLabel: String {
        controller.canvasLoadError ?? "涂鸦交互遮罩"
    }
}

struct LibraryDoodleToolbarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
                    .frame(width: 30, height: 30)
                    .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
            }
    }
}

/// Mounts PencilKit in the detail page's content coordinate space. The view is
/// attached to the scroll content instead of the window overlay; scrolling
/// therefore moves the text, images, and strokes together without serializing
/// the drawing on every offset change.
struct LibraryDoodleContentLayer: View {
    @ObservedObject var session: LibraryDoodleSession
    let targetRecordID: String
    private let hostIdentifier: String?
    var minimumCanvasHeight: CGFloat = 260
    @ObservedObject private var canvas: LibraryDoodleCanvasState
    @ObservedObject private var controller: PencilDrawingController

    private var canvasFramePreferenceID: String {
        "\(targetRecordID)|\(controller.drawingLoadRevision)"
    }

    init(
        session: LibraryDoodleSession,
        targetRecordID: String,
        canvasHostID: String? = nil,
        minimumCanvasHeight: CGFloat = 260
    ) {
        self.session = session
        self.targetRecordID = targetRecordID
        hostIdentifier = canvasHostID
        self.minimumCanvasHeight = minimumCanvasHeight
        _canvas = ObservedObject(wrappedValue: session.canvas)
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    private var canvasHostID: String { hostIdentifier ?? targetRecordID }

    var body: some View {
        Group {
            if session.shouldMountCanvas(for: targetRecordID, hostID: canvasHostID) {
                GeometryReader { proxy in
                    NativePencilDrawingEditor(
                        encodedData: $canvas.drawingData,
                        legacyPreviewDataURL: canvas.legacyPreviewDataURL,
                        transparentBackground: true,
                        toolbarAtTop: false,
                        isActive: session.isPresented && session.isCanvasActivationReady,
                        minimumCanvasHeight: minimumCanvasHeight,
                        settingsPanelPresentedExternally: true,
                        controller: controller,
                        onClose: session.dismiss
                    )
                    .onAppear { session.noteCanvasHostMounted(canvasHostID) }
                    .onDisappear { session.noteCanvasHostUnmounted(canvasHostID) }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .preference(
                        key: LibraryDoodleCanvasFramePreferenceKey.self,
                        value: [canvasFramePreferenceID: proxy.frame(in: .global)]
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: minimumCanvasHeight)
                .contentShape(Rectangle())
                .opacity(session.isPresented ? 1 : 0)
                .allowsHitTesting(session.isPresented && session.isCanvasActivationReady)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("library-doodle-content-layer-\(targetRecordID)")
            }
        }
        .onPreferenceChange(LibraryDoodleCanvasFramePreferenceKey.self) { frames in
            guard session.targetRecordID == targetRecordID else { return }
            guard let frame = frames[canvasFramePreferenceID] else {
                if session.canvas.canvasFrameOwnerID == canvasFramePreferenceID {
                    session.canvas.canvasFrameInGlobal = nil
                    session.canvas.canvasFrameOwnerID = nil
                }
                return
            }
            session.canvas.canvasFrameInGlobal = frame
            session.canvas.canvasFrameOwnerID = canvasFramePreferenceID
            session.noteCanvasFramePreference()
        }
        .onDisappear {
            session.noteCanvasHostUnmounted(canvasHostID)
            guard session.targetRecordID == targetRecordID,
                  session.canvas.canvasFrameOwnerID == canvasFramePreferenceID else { return }
            session.canvas.canvasFrameInGlobal = nil
            session.canvas.canvasFrameOwnerID = nil
        }
    }
}

/// One split-pane PencilKit surface. The selected pane receives input while the
/// other pane keeps a read-only drawing in the same scrolling content space.
struct LibraryDoodleSplitContentLayer: View {
    @ObservedObject var session: LibraryDoodleSession
    let targetRecordID: String
    let pane: LibraryDoodlePane
    let layoutDirection: LibraryDoodleLayoutDirection
    private let hostNamespace: String
    @Binding var drawingData: String
    var minimumCanvasHeight: CGFloat = 260
    @ObservedObject private var controller: PencilDrawingController

    private var framePreferenceID: String {
        "\(targetRecordID)|split|\(layoutDirection.rawValue)|\(pane.rawValue)|\(controller.drawingLoadRevision)"
    }

    private var isCurrentSplitSession: Bool {
        session.targetRecordID == targetRecordID
            && ((session.isCanvasActivationReady && session.isSplitDrawingSession)
                || session.mountedCanvasHostID == canvasHostID)
    }

    private var canvasHostID: String {
        "\(hostNamespace)|\(targetRecordID)|split|\(layoutDirection.rawValue)|\(pane.rawValue)"
    }

    private var isActiveTarget: Bool {
        session.isPresented && session.isCanvasActivationReady
            && isCurrentSplitSession && session.activeSplitDrawingPane == pane
    }

    init(
        session: LibraryDoodleSession,
        targetRecordID: String,
        pane: LibraryDoodlePane,
        layoutDirection: LibraryDoodleLayoutDirection,
        drawingData: Binding<String>,
        hostNamespace: String = "split",
        minimumCanvasHeight: CGFloat = 260
    ) {
        self.session = session
        self.targetRecordID = targetRecordID
        self.pane = pane
        self.layoutDirection = layoutDirection
        self.hostNamespace = hostNamespace
        _drawingData = drawingData
        self.minimumCanvasHeight = minimumCanvasHeight
        _controller = ObservedObject(wrappedValue: session.canvas.controller)
    }

    var body: some View {
        Group {
            if isCurrentSplitSession {
                GeometryReader { proxy in
                    Group {
                        if isActiveTarget || session.mountedCanvasHostID == canvasHostID {
                            NativePencilDrawingEditor(
                                encodedData: $drawingData,
                                transparentBackground: true,
                                toolbarAtTop: false,
                                isActive: isActiveTarget,
                                minimumCanvasHeight: minimumCanvasHeight,
                                settingsPanelPresentedExternally: true,
                                controller: controller,
                                onClose: session.dismiss
                            )
                            .onAppear { session.noteCanvasHostMounted(canvasHostID) }
                            .onDisappear { session.noteCanvasHostUnmounted(canvasHostID) }
                        } else {
                            NativePencilDrawingPreview(encodedData: drawingData)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .preference(
                        key: LibraryDoodleCanvasFramePreferenceKey.self,
                        value: isActiveTarget ? [framePreferenceID: proxy.frame(in: .global)] : [:]
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minHeight: minimumCanvasHeight)
                .contentShape(Rectangle())
                .allowsHitTesting(isActiveTarget)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("library-doodle-split-layer-\(pane.rawValue)-\(targetRecordID)")
            } else {
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .frame(minHeight: minimumCanvasHeight)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }
        }
        .onAppear {
            if isCurrentSplitSession && isActiveTarget {
                session.noteCanvasHostMounted(canvasHostID)
            }
        }
        .onDisappear { session.noteCanvasHostUnmounted(canvasHostID) }
        .onPreferenceChange(LibraryDoodleCanvasFramePreferenceKey.self) { frames in
            guard isActiveTarget else { return }
            guard let frame = frames[framePreferenceID] else {
                clearCanvasFrameIfOwned()
                return
            }
            session.canvas.canvasFrameInGlobal = frame
            session.canvas.canvasFrameOwnerID = framePreferenceID
            session.noteCanvasFramePreference()
        }
        .onChange(of: isActiveTarget) { _, isActive in
            guard !isActive else { return }
            clearCanvasFrameIfOwned()
        }
        .onDisappear(perform: clearCanvasFrameIfOwned)
    }

    private func clearCanvasFrameIfOwned() {
        guard session.canvas.canvasFrameOwnerID == framePreferenceID else { return }
        session.canvas.canvasFrameInGlobal = nil
        session.canvas.canvasFrameOwnerID = nil
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
