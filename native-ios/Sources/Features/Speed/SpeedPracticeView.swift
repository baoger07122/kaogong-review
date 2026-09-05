import SwiftData
import SwiftUI
import UIKit

struct SpeedPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var keySound = SpeedKeySound()
    @Query private var records: [StoredRecord]
    @State private var screen: SpeedScreen = .home
    @State private var settings = SpeedSettings()
    @State private var estimateRows: [SpeedEstimateRow] = []
    @State private var questions: [SpeedQuestion] = []
    @State private var index = 0
    @State private var currentInput = ""
    @State private var inputRevision = 0
    @State private var startedAt = Date()
    @State private var questionStartedAt = Date()
    @State private var selectedHistory: SpeedRecord?
    @State private var savedResultID: String?
    @State private var didLoad = false
    @State private var showSettings = false
    @State private var showCustomSettings = false
    @State private var showExitConfirmation = false
    @State private var showLegacyExitConfirmation = false
    @State private var exitMeasurements = ""
    @State private var expandedHistoryBlocks: Set<String> = []
    @State private var isSubmitting = false
    @State private var feedback: SpeedFeedbackMessage?
    @State private var finishedDuration: Double?
    @State private var showDoodle = false
    @State private var drawingData = ""
    @StateObject private var doodleController = PencilDrawingController()

    private var practiceTitle: String {
        settings.useCustomPractice == true || activeTypes.count > 1 ? "自定义练习" : (questions.first?.type.name ?? settings.selectedType.name)
    }

    private var history: [SpeedRecord] { SpeedRepository.history(from: records).sorted { $0.date > $1.date } }
    private var historyGroups: [SpeedHistoryDayGroup] { SpeedHistoryGrouping.groups(history) }

    private var screenTitle: String {
        switch screen {
        case .home: "速算练习"
        case .practice, .result: practiceTitle
        case .history: selectedHistory?.name ?? "历史记录"
        case .statistics: "速算统计"
        case .estimateTable: "估算表"
        }
    }

    private func navigateBack() {
        guard !isSubmitting else { return }
        guard !showDoodle else { return }
        if screen == .history, selectedHistory != nil {
            selectedHistory = nil
        } else if screen == .practice {
            SpeedExitDiagnostics.begin()
            if SpeedExitDiagnostics.useSystemAlert { showLegacyExitConfirmation = true }
            else {
                var transaction = Transaction()
                transaction.animation = nil
                transaction.disablesAnimations = true
                withTransaction(transaction) { showExitConfirmation = true }
            }
        } else {
            screen = .home
        }
    }

    private var presentedContent: some View {
        ZStack {
            Group {
                switch screen {
                case .home: home
                case .practice: practice
                case .result: result
                case .history: historyView
                case .statistics: statistics
                case .estimateTable: estimateTable
                }
            }
            .allowsHitTesting(!showDoodle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            (settings.nightMode ? Color.black : Color.white).ignoresSafeArea()
        }
        .overlay(alignment: .top) {
            if let feedback {
                SpeedFeedbackToast(message: feedback, nightMode: settings.nightMode)
                    .padding(.top, 16).allowsHitTesting(false)
            }
        }
        .overlay {
            if showExitConfirmation {
                SpeedExitConfirmation(onContinue: { showExitConfirmation = false }, onExit: abandon)
                    .onAppear { SpeedExitDiagnostics.mark("dialog") }
            }
        }
        .background { SpeedExitTouchProbe() }
        .overlay {
            if showDoodle {
                ZStack {
                    Color.black.opacity(0.18).ignoresSafeArea().allowsHitTesting(false)
                    NativePencilDrawingEditor(encodedData: $drawingData, transparentBackground: true, controller: doodleController, onClose: closeDoodle)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .preference(key: RootBottomBarHiddenPreferenceKey.self, value: screen != .home)
        .foregroundStyle(settings.nightMode ? Color.white : Color.primary)
    }

    @ToolbarContentBuilder
    private var speedToolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { backControl }
        ToolbarItem(placement: .topBarTrailing) { trailingControls }
            .documentToolbarBackground()
    }

    @ViewBuilder
    private var backControl: some View {
        if screen != .home {
            Button(action: navigateBack) {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .accessibilityLabel("返回")
            .accessibilityIdentifier("speed-back")
            .disabled(isSubmitting)
            .allowsHitTesting(!showDoodle)
            .accessibilityHidden(showDoodle)
            .opacity(showDoodle ? 0.32 : 1)
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if showDoodle {
            NativeDoodleToolbarCapsule {
                doodleButton("xmark", "退出涂鸦", action: closeDoodle)
                    .accessibilityIdentifier("speed-doodle-close")
                doodleButton(doodleController.eraser ? "eraser.fill" : "eraser", "橡皮擦", active: doodleController.eraser, action: doodleController.toggleEraser)
                doodleButton("arrow.uturn.backward", "撤销", action: doodleController.undo)
                doodleButton("trash", "清空涂鸦", action: doodleController.requestClear)
                doodleButton("paintpalette", "画笔调节", active: doodleController.showSettings) { doodleController.showSettings.toggle() }
                doodleButton(
                    "hand.draw",
                    doodleController.fingerDrawingEnabled ? "关闭手指涂鸦" : "开启手指涂鸦",
                    active: doodleController.fingerDrawingEnabled
                ) { doodleController.fingerDrawingEnabled.toggle() }
            }
        } else if screen == .practice || screen == .result || (screen == .history && selectedHistory != nil) {
            Button(action: openDoodle) {
                Image(systemName: "pencil.and.scribble")
                    .frame(width: 36, height: 36)
                    .contentShape(Circle())
            }
            .accessibilityLabel("涂鸦")
        }
    }

    var body: some View {
        presentedContent
        .navigationTitle(screenTitle)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(screen != .home)
        .toolbar { speedToolbar }
        .alert("退出练习", isPresented: $showLegacyExitConfirmation) {
            Button("退出", role: .destructive, action: abandon)
            Button("继续", role: .cancel) { }
        } message: { Text("当前练习进度将丢失，确定退出吗？") }
        .task(id: feedback?.id) {
            guard feedback != nil else { return }
            do { try await Task.sleep(for: .milliseconds(2500)) } catch { return }
            guard !Task.isCancelled else { return }
            feedback = nil
        }
        .onDisappear { keySound.stop() }
        .sheet(isPresented: $showSettings) { practiceSettingsSheet }
        .sheet(isPresented: $showCustomSettings) { customPracticeSheet }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, screen == .practice, settings.soundEnabled != false {
                keySound.prepare()
            } else {
                keySound.stop()
            }
        }
        .task {
            guard !didLoad else { return }
            didLoad = true
            settings = SpeedRepository.settings(from: records)
            if ![10, 15, 20].contains(settings.questionCount) {
                settings.questionCount = 10
                persistSettings()
            }
            estimateRows = SpeedRepository.estimateRows(from: records)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    speedActionChip("历史", image: "clock.arrow.circlepath") { screen = .history }
                    speedActionChip("统计", image: "chart.bar.fill") { screen = .statistics }
                    speedActionChip("估算表", image: "tablecells") { screen = .estimateTable }
                    Spacer()
                    speedActionChip("设置", image: "slider.horizontal.3") { showSettings = true }
                }

                speedModuleCard(
                    title: "基础计算",
                    image: "abacus",
                    values: SpeedTypeKey.allCases.filter { !$0.isDataAnalysis },
                    includesCustomPractice: true
                )
                speedModuleCard(
                    title: "资料分析",
                    image: "chart.line.uptrend.xyaxis",
                    values: SpeedTypeKey.allCases.filter(\.isDataAnalysis)
                )

                HStack(spacing: 12) {
                    Menu {
                        ForEach([10, 15, 20], id: \.self) { count in
                            Button("\(count) 题") { settings.questionCount = count; persistSettings() }
                        }
                    } label: {
                        speedOptionLabel("题量: \(settings.questionCount)")
                    }
                    Menu {
                        ForEach(SpeedMode.allCases) { mode in
                            Button(mode.rawValue) { settings.mode = mode; persistSettings() }
                        }
                    } label: {
                        speedOptionLabel("模式: \(settings.mode.rawValue)")
                    }
                }
                .frame(maxWidth: .infinity)

                Button(action: start) {
                    Text(startButtonTitle)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(canStart ? AppTheme.accent : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canStart)
                .accessibilityIdentifier("speed-start")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .padding(.bottom, 12)
        }
        .background(Color.white)
        .background {
            SpeedExitFrameProbe { exitMeasurements = SpeedExitDiagnostics.finish() }
        }
        .overlay(alignment: .bottomLeading) {
            if SpeedExitDiagnostics.enabled, !exitMeasurements.isEmpty {
                Text(exitMeasurements).font(.system(size: 8))
                    .accessibilityIdentifier("speed-exit-metrics").allowsHitTesting(false)
            }
        }
    }

    private func typeGrid(_ values: [SpeedTypeKey], includesCustomPractice: Bool = false) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(values) { type in
                Button {
                    settings.selectedType = type
                    settings.useCustomPractice = false
                    if type.isAvailable { settings.customTypes = [type] }
                    persistSettings()
                } label: {
                    HStack(spacing: 9) {
                        Text(typeSymbol(type))
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(settings.selectedType == type ? Color.white : AppTheme.accent)
                            .frame(width: 30, height: 30)
                            .background(
                                settings.selectedType == type ? AppTheme.accent : AppTheme.accent.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(type.name).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.82)
                            Text(typeSubtitle(type))
                                .font(.system(size: 9, weight: .regular)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(9)
                    .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                    .background(
                        settings.selectedType == type ? AppTheme.accent.opacity(0.10) : Color(red: 0.973, green: 0.98, blue: 1),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(settings.selectedType == type ? AppTheme.accent : AppTheme.accent.opacity(0.16), lineWidth: settings.selectedType == type ? 1.2 : 0.7)
                    }
                    .shadow(color: settings.selectedType == type ? AppTheme.accent.opacity(0.18) : .clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!type.isAvailable)
                .accessibilityIdentifier("speed-type-\(type.rawValue)")
            }
            if includesCustomPractice { customPracticeCard }
        }
    }

    private func speedModuleCard(title: String, image: String, values: [SpeedTypeKey], includesCustomPractice: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: image)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 11))
                Text(title).font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(values.filter(\.isAvailable).count)/\(values.count) 可练习")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
            }
            typeGrid(values, includesCustomPractice: includesCustomPractice)
        }
        .padding(12)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.045), lineWidth: 0.6) }
    }

    private func speedActionChip(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 13)
                .frame(height: 34)
                .background(Color(red: 0.96, green: 0.96, blue: 0.97), in: Capsule())
        }
        .buttonStyle(NativePressButtonStyle())
    }

    private func speedOptionLabel(_ title: String) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(AppTheme.accent)
        .padding(.horizontal, 18)
        .frame(height: 42)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(AppTheme.accent.opacity(0.28), lineWidth: 1) }
    }

    private func typeSymbol(_ type: SpeedTypeKey) -> String {
        switch type {
        case .addsub2, .addsub3: "±"
        case .add3: "+"
        case .sub3: "−"
        case .mul2x1, .mul3x1: "×"
        case .div3x1, .div5x3: "÷"
        case .spDen: "%"
        case .est05: "≈"
        case .base: "↗"
        case .growth: "▥"
        case .dataReal: "▣"
        }
    }

    private func typeSubtitle(_ type: SpeedTypeKey) -> String {
        guard type.isAvailable else { return "即将上线" }
        guard let pass = type.ratingThresholds?.pass else { return "可练习" }
        return "合格 \(Int(pass))s"
    }

    private var customPracticeCard: some View {
        Button {
            if settings.customNumberMode == nil || settings.customNumberMode == .none { settings.customNumberMode = .range }
            showCustomSettings = true
        } label: {
            HStack(spacing: 9) {
                Text("+")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(settings.useCustomPractice == true ? Color.white : AppTheme.accent)
                    .frame(width: 30, height: 30)
                    .background(settings.useCustomPractice == true ? AppTheme.accent : AppTheme.accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text("自定义练习").font(.system(size: 12, weight: .medium))
                        Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
                    }
                    Text("自选题型组合").font(.system(size: 9)).foregroundStyle(AppTheme.accent)
                }
                Spacer(minLength: 0)
            }
            .padding(9)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(settings.useCustomPractice == true ? AppTheme.accent.opacity(0.10) : Color(red: 0.973, green: 0.98, blue: 1), in: RoundedRectangle(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(settings.useCustomPractice == true ? AppTheme.accent : AppTheme.accent.opacity(0.16), lineWidth: 0.8) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }

    private var customPracticeSheet: some View {
        VStack(spacing: 0) {
            Capsule().fill(Color.secondary.opacity(0.28)).frame(width: 38, height: 5).padding(.top, 8)
            HStack {
                Text("自定义练习").font(.system(size: 18, weight: .semibold))
                Spacer()
                Button { showCustomSettings = false } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
                        .frame(width: 30, height: 30)
                        .background(Color.primary.opacity(0.06), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("题型选择").font(.system(size: 16, weight: .semibold))
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
                        ForEach(SpeedTypeKey.allCases.filter(\.isAvailable)) { type in
                            Button {
                                settings.customTypes = settings.customTypes == [type] ? [] : [type]
                            } label: {
                                Text(type.name)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(settings.customTypes == [type] ? Color.white : Color.primary)
                                    .frame(maxWidth: .infinity).frame(height: 40)
                                    .background(settings.customTypes == [type] ? AppTheme.accent : Color.white, in: RoundedRectangle(cornerRadius: 10))
                                    .overlay { RoundedRectangle(cornerRadius: 10).stroke(settings.customTypes == [type] ? AppTheme.accent : Color.primary.opacity(0.09), lineWidth: 0.7) }
                            }
                            .buttonStyle(SpeedKeyButtonStyle())
                        }
                    }

                    Text("数字设置").font(.system(size: 16, weight: .semibold))
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 3) {
                            customModeButton("数字范围", mode: .range)
                            customModeButton("固定数字", mode: .fixed)
                        }
                        .padding(3)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))

                        if settings.customNumberMode == .fixed {
                            Text("选择一个或多个固定数字").font(.system(size: 13)).foregroundStyle(.secondary)
                            HStack(spacing: 8) {
                                ForEach(2...9, id: \.self) { number in
                                    Button { toggleFixedNumber(number) } label: {
                                        Text("\(number)").font(.system(size: 16, weight: .medium).monospacedDigit())
                                            .foregroundStyle(selectedFixedNumbers.contains(number) ? Color.white : Color.primary)
                                            .frame(maxWidth: .infinity).frame(height: 44)
                                            .background(selectedFixedNumbers.contains(number) ? AppTheme.accent : Color.white, in: RoundedRectangle(cornerRadius: 10))
                                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.09), lineWidth: 0.7) }
                                    }.buttonStyle(SpeedKeyButtonStyle())
                                }
                            }
                        } else {
                            Text("在范围内随机出题").font(.system(size: 13)).foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                customRangeField("最小值", value: customRangeMinimumBinding)
                                Text("～").foregroundStyle(.secondary)
                                customRangeField("最大值", value: customRangeMaximumBinding)
                            }
                        }
                    }
                    .padding(16)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))

                    Text("最近使用").font(.system(size: 16, weight: .semibold))
                    if let selected = settings.customTypes.first {
                        Text("\(selected.name) · \(customSettingSummary)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(13)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 18)
            }

            HStack(spacing: 12) {
                Button("取消") { showCustomSettings = false }
                    .buttonStyle(NativeSecondaryButtonStyle())
                Button("确定") {
                    settings.useCustomPractice = true
                    if settings.customNumberMode == nil || settings.customNumberMode == .none { settings.customNumberMode = .range }
                    persistSettings()
                    showCustomSettings = false
                }
                .buttonStyle(NativePrimaryButtonStyle())
                .disabled(settings.customTypes.isEmpty || (settings.customNumberMode == .fixed && selectedFixedNumbers.isEmpty))
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 12)
            .background(.ultraThinMaterial)
        }
        .background(Color(red: 0.961, green: 0.961, blue: 0.98))
        .presentationDetents([.large])
    }

    private func customModeButton(_ title: String, mode: SpeedCustomNumberMode) -> some View {
        Button {
            settings.customNumberMode = mode
        } label: {
            Text(title).font(.system(size: 14, weight: .medium))
                .foregroundStyle(settings.customNumberMode == mode ? Color.white : Color.secondary)
                .padding(.horizontal, 22).frame(height: 34)
                .background(settings.customNumberMode == mode ? AppTheme.accent : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }.buttonStyle(.plain)
    }

    private func customRangeField(_ title: String, value: Binding<Int>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(title, value: value, format: .number)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .keyboardType(.numberPad).multilineTextAlignment(.center)
                .frame(height: 44)
                .background(Color.primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.10), lineWidth: 0.8) }
        }
    }

    private var customSettingSummary: String {
        if settings.customNumberMode == .fixed { return "固定数字 \(selectedFixedNumbers.map(String.init).joined(separator: "、"))" }
        return "数字范围 \(settings.customRangeMinimum ?? 1)–\(settings.customRangeMaximum ?? 99)"
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("使用屏幕数字键盘", isOn: settingBinding(\.useScreenKeyboard))
            Toggle("按所选题型顺序出题", isOn: settingBinding(\.sequential))
            Toggle("夜间模式", isOn: settingBinding(\.nightMode))
            Toggle("结果不出现负数", isOn: settingBinding(\.noNegative))
            Toggle("按键音效", isOn: soundEnabledBinding)
        }
        .font(AppTheme.inputFont)
        .padding(15)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var practiceSettingsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("手动确认：输入答案后，点击键盘 ✓ 提交。")
                        .font(AppTheme.inputFont).foregroundStyle(.secondary)
                    HStack {
                        Text("题目数量")
                        Spacer()
                        Picker("题目数量", selection: settingBinding(\.questionCount)) {
                            ForEach([10, 15, 20], id: \.self) { Text("\($0) 题").tag($0) }
                        }
                    }
                    HStack {
                        Text("练习模式")
                        Spacer()
                        Picker("练习模式", selection: settingBinding(\.mode)) {
                            ForEach(SpeedMode.allCases) { Text($0.rawValue).tag($0) }
                        }
                    }
                    .font(AppTheme.inputFont)
                    settingsCard
                }
                .padding(18)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("练习设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showSettings = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var practice: some View {
        GeometryReader { geometry in
        let sizing = SpeedKeypadMetrics.practiceSizing(
            contentHeight: geometry.size.height,
            viewportHeight: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom,
            questionHeight: questions.indices.contains(index) && questions[index].type == .est05 ? 244 : 88
        )
        VStack(spacing: 0) {
            if questions.indices.contains(index) {
                let question = questions[index]
                VStack(spacing: 0) {
                    HStack {
                        Text("\(index + 1)/\(questions.count)")
                            .foregroundStyle(settings.nightMode ? Color.white : Color.primary)
                        Spacer()
                        TimelineView(.periodic(from: .now, by: 0.1)) { context in
                            Text(String(format: "%d:%04.1f", Int(context.date.timeIntervalSince(startedAt)) / 60, context.date.timeIntervalSince(startedAt).truncatingRemainder(dividingBy: 60)))
                                .monospacedDigit()
                        }
                    }
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 20)
                    .frame(height: 52)
                    Divider()

                    Spacer(minLength: 12)
                    if let estimate = question.estimate {
                        SpeedEstimateExercise(problem: estimate, input: currentInput, nightMode: settings.nightMode)
                    } else {
                        SpeedAnswerRow(expression: question.expression, input: currentInput,
                                       questionID: question.id, inputRevision: inputRevision, nightMode: settings.nightMode)
                    }
                    Spacer(minLength: 12)
                    if settings.useScreenKeyboard {
                        SpeedNumberPad(
                            metrics: SpeedKeypadMetrics(width: geometry.size.width, height: sizing.keyboard,
                                bottomInset: geometry.safeAreaInsets.bottom),
                            onPress: { if settings.soundEnabled != false { keySound.play() } },
                            onKey: pressKey,
                            onClear: { pressKey("⌫") },
                            onBackspace: { pressKey("C") },
                            onSubmit: submit
                        )
                        .allowsHitTesting(!isSubmitting)
                        Color.clear.frame(height: sizing.footer)
                    } else {
                        TextField("答案", text: $currentInput)
                            .keyboardType(.decimalPad)
                            .submitLabel(.done)
                            .onSubmit(submit)
                            .disabled(isSubmitting)
                            .textFieldStyle(NativeTextFieldStyle())
                        Button("确认答案", action: submit)
                            .buttonStyle(NativePrimaryButtonStyle())
                            .disabled(isSubmitting)
                            .padding(12)
                    }

                }
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            }
        }
        }
        .onAppear { if settings.soundEnabled != false { keySound.prepare() } }
        .onDisappear {
            SpeedExitDiagnostics.mark("audioStart")
            keySound.stop()
            SpeedExitDiagnostics.mark("audioEnd")
        }
    }

    private var result: some View {
        SpeedResultView(questions: questions, title: practiceTitle, totalTime: totalTime, standard: resultStandardText, onRestart: start, onRetry: retryWrong, onReturn: { screen = .home })
        .task { saveResultIfNeeded() }
    }

    private var historyView: some View {
        Group {
            if let record = selectedHistory {
                SpeedResultView(
                    questions: record.details,
                    title: record.name,
                    totalTime: record.totalTime,
                    standard: "",
                    onRestart: {},
                    onRetry: {},
                    onReturn: {},
                    showsStandard: false,
                    showsFooter: false
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("按练习类型对比")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(.bottom, 12)
                        if history.isEmpty {
                            NativeStatusCard(title: "暂无练习历史", detail: "完成一轮练习后自动保存", systemImage: "clock", color: AppTheme.accent)
                        } else {
                            ForEach(historyGroups) { group in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(historySectionTitle(group.date))
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                    ForEach(group.blocks) { block in historyBlock(block) }
                                }
                                .padding(.bottom, 18)
                            }
                        }
                    }
                    .padding(20)
                }
            }
        }
    }

    private func historyBlock(_ block: SpeedHistoryBlock) -> some View {
        VStack(spacing: 0) {
            Button {
                if expandedHistoryBlocks.contains(block.id) { expandedHistoryBlocks.remove(block.id) }
                else { expandedHistoryBlocks.insert(block.id) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 36, height: 36)
                        .background(Color(red: 231 / 255.0, green: 240 / 255.0, blue: 1), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(block.name).font(.system(size: 14, weight: .semibold))
                        Text("共 \(block.records.count) 次 · \(block.totalCount) 题")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(Int((block.accuracy * 100).rounded()))%")
                            .font(.system(size: 18, weight: .bold)).foregroundStyle(AppTheme.accent)
                        Text("\(Int(block.totalTime.rounded()))秒")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                    Image(systemName: expandedHistoryBlocks.contains(block.id) ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 24)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expandedHistoryBlocks.contains(block.id) {
                VStack(spacing: 0) {
                    ForEach(block.records) { record in
                        Button {
                            drawingData = ""
                            selectedHistory = record
                        } label: {
                            HStack(spacing: 8) {
                                Text(record.date.formatted(.dateTime.hour().minute()))
                                Text("\(record.totalCount)题")
                                Spacer()
                                Text("\(record.correctCount)/\(record.totalCount)")
                                Text(SpeedPracticeFlow.durationText(record.totalTime))
                                Image(systemName: "chevron.right").font(.system(size: 9))
                            }
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 58).padding(.trailing, 12)
                            .frame(height: 38)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottom) { Color.primary.opacity(0.045).frame(height: 0.5) }
                    }
                }
                .background(Color(red: 250 / 255, green: 250 / 255, blue: 252 / 255))
                .overlay(alignment: .top) { Color.primary.opacity(0.045).frame(height: 0.5) }
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.09), lineWidth: 0.7) }
    }

    private func historySectionTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInYesterday(date) { return "昨天" }
        return date.formatted(.dateTime.month().day())
    }

    private var statistics: some View {
        let snapshot = SpeedStatisticsSnapshot(records: history)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let hot = snapshot.hottest {
                    HStack(spacing: 12) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                            .frame(width: 44, height: 44)
                            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("最常练习").font(.system(size: 12)).foregroundStyle(.secondary)
                            Text(hot.name).font(.system(size: 16, weight: .semibold))
                        }
                        Spacer()
                        statisticValue("\(hot.practiceCount)", caption: "练习次数")
                        statisticValue("\(Int((hot.accuracy * 100).rounded()))%", caption: "正确率")
                        statisticValue(SpeedPracticeFlow.durationText(hot.averageTime), caption: "10题平均")
                    }
                    .padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                    .shadow(color: .black.opacity(0.04), radius: 5, y: 2)
                } else {
                    NativeStatusCard(title: "暂无统计数据", detail: "完成练习后生成统计", systemImage: "chart.bar", color: AppTheme.accent)
                }
                if !history.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("近 7 天正确率").font(.system(size: 14, weight: .semibold))
                        SpeedAccuracyTrendChart(days: snapshot.trend).frame(height: 155)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading, spacing: 12) {
                        Text("练习类型用时").font(.system(size: 14, weight: .semibold))
                        let maxAverage = snapshot.longestFour.map(\.averageTime).max() ?? 1
                        ForEach(snapshot.longestFour) { aggregate in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(aggregate.name).font(.system(size: 13))
                                    Spacer()
                                    Text("平均 \(SpeedPracticeFlow.durationText(aggregate.averageTime))")
                                        .font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                GeometryReader { proxy in
                                    Capsule().fill(AppTheme.accent.opacity(0.12))
                                    Capsule().fill(AppTheme.accent)
                                        .frame(width: proxy.size.width * max(0.03, aggregate.averageTime / max(maxAverage, 0.01)))
                                }
                                .frame(height: 7)
                            }
                        }
                    }
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 20))
                }
            }
            .padding(20)
            .background(Color(uiColor: .systemGroupedBackground))
        }
    }

    private func statisticValue(_ value: String, caption: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .bold)).foregroundStyle(AppTheme.accent)
            Text(caption).font(.system(size: 10)).foregroundStyle(.secondary)
        }
        .frame(minWidth: 62)
    }

    private var estimateTable: some View {
        SpeedEstimateTableView(rows: estimateRows) { updated in
            try SpeedRepository.saveEstimateRows(updated, records: records, context: modelContext)
            estimateRows = updated
        }
    }

    private var activeTypes: [SpeedTypeKey] {
        let custom = settings.customTypes.filter(\.isAvailable)
        return settings.useCustomPractice == true ? custom : (settings.selectedType.isAvailable ? [settings.selectedType] : [])
    }

    private var canStart: Bool {
        guard (settings.useCustomPractice == true || settings.selectedType != .dataReal), !activeTypes.isEmpty else { return false }
        guard settings.useCustomPractice == true else { return true }
        if settings.customNumberMode == .fixed { return !selectedFixedNumbers.isEmpty }
        if settings.customNumberMode == .range, activeTypes.contains(.div3x1) {
            return max(2, settings.customRangeMinimum ?? 1) <= min(9, settings.customRangeMaximum ?? 99)
        }
        return true
    }

    private var startButtonTitle: String {
        if settings.useCustomPractice != true, settings.selectedType == .dataReal { return "该题型尚未开放" }
        if settings.useCustomPractice == true, !canStart { return "请选择有效数字（三位数除一位数：2–9）" }
        return settings.useCustomPractice == true ? "开始自定义练习" : "开始练习"
    }

    private var memoBinding: Binding<String> {
        Binding(get: { questions.indices.contains(index) ? questions[index].memo : "" }, set: { if questions.indices.contains(index) { questions[index].memo = $0 } })
    }

    private var soundEnabledBinding: Binding<Bool> {
        Binding(
            get: { settings.soundEnabled ?? true },
            set: { settings.soundEnabled = $0; persistSettings() }
        )
    }

    private var customNumberModeBinding: Binding<SpeedCustomNumberMode> {
        Binding(
            get: { settings.customNumberMode ?? .none },
            set: { settings.customNumberMode = $0; persistSettings() }
        )
    }

    private var customRangeMinimumBinding: Binding<Int> {
        Binding(
            get: { settings.customRangeMinimum ?? 1 },
            set: { settings.customRangeMinimum = min(max(1, $0), 999); persistSettings() }
        )
    }

    private var customRangeMaximumBinding: Binding<Int> {
        Binding(
            get: { settings.customRangeMaximum ?? 99 },
            set: { settings.customRangeMaximum = min(max(1, $0), 999); persistSettings() }
        )
    }

    private var selectedFixedNumbers: [Int] {
        (settings.customFixedNumbers ?? []).filter { (activeTypes.contains(.div3x1) ? 2...9 : 1...9).contains($0) }
    }

    private var correctCount: Int { questions.filter { $0.isCorrect == true }.count }
    private var totalTime: Double { finishedDuration ?? questions.reduce(0) { $0 + $1.timeUsed } }

    private var resultStandardText: String {
        let fallback = SpeedRatingThresholds(excellent: 18, good: 22, pass: 28)
        let firstType = questions.first?.type
        let usesSingleType = firstType.map { type in questions.allSatisfy { $0.type == type } } ?? false
        let thresholds = usesSingleType && settings.useCustomPractice != true ? firstType?.ratingThresholds ?? fallback : fallback
        return "误差 ±3%   合格: \(Int(thresholds.pass))s  良好: \(Int(thresholds.good))s  优秀: \(Int(thresholds.excellent))s"
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<SpeedSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; persistSettings() })
    }

    private func start() {
        guard canStart else { return }
        exitMeasurements = ""
        let generated = SpeedQuestionEngine.questions(
            types: activeTypes,
            count: settings.questionCount,
            sequential: settings.sequential,
            estimates: estimateRows,
            customMode: settings.useCustomPractice == true ? settings.customNumberMode : nil,
            fixedNumbers: selectedFixedNumbers,
            rangeMinimum: settings.customRangeMinimum ?? 1,
            rangeMaximum: settings.customRangeMaximum ?? 99
        )
        guard !generated.isEmpty else { return }
        resetAttemptState()
        questions = generated
        index = 0
        currentInput = ""
        startedAt = .now
        questionStartedAt = .now
        savedResultID = nil
        screen = .practice
    }

    private func submit() {
        guard screen == .practice, !isSubmitting, questions.indices.contains(index), questions[index].isCorrect == nil else { return }
        guard SpeedPracticeFlow.canSubmit(questions[index], input: currentInput) else {
            feedback = SpeedFeedbackMessage(text: "请输入有效答案", success: nil)
            return
        }
        isSubmitting = true
        questions[index].input = currentInput
        questions[index].timeUsed = Date.now.timeIntervalSince(questionStartedAt)
        questions[index].isCorrect = SpeedQuestionEngine.isCorrect(input: currentInput, answer: questions[index].answer, type: questions[index].type)
        let success = questions[index].isCorrect == true
        if index == questions.count - 1 { finishedDuration = Date.now.timeIntervalSince(startedAt) }
        let message = questions[index].type == .div3x1 && settings.useCustomPractice != true
            ? (success ? rating(for: questions[index]).rawValue + "！" : "✗ ") + String(format: "%.1fs", questions[index].timeUsed)
            : (success ? "✓" : "✗")
        feedback = SpeedFeedbackMessage(text: message, success: success)
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        // Grade and advance in the same event. Feedback is a separate non-blocking overlay.
        // The graded-question guard and cleared next answer prevent a second grading.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { advance() }
    }

    private func advance() {
        isSubmitting = false
        showDoodle = false
        currentInput = ""
        if index + 1 >= questions.count {
            saveResultIfNeeded()
            screen = .result
        } else {
            index += 1
            drawingData = ""
            questionStartedAt = .now
        }
    }

    private func abandon() {
        SpeedExitDiagnostics.mark("exit")
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            showExitConfirmation = false
            resetAttemptState()
            questions = []
            currentInput = ""
            screen = .home
        }
        SpeedExitDiagnostics.mark("state")
    }

    private func pressKey(_ key: String) {
        guard screen == .practice, !isSubmitting else { return }
        currentInput = SpeedKeyInput.applying(key, to: currentInput)
        inputRevision &+= 1
    }

    private func resetAttemptState() {
        isSubmitting = false
        feedback = nil
        inputRevision = 0
        finishedDuration = nil
        showDoodle = false
        drawingData = ""
        savedResultID = nil
    }

    private func retryWrong() {
        let retry = SpeedPracticeFlow.retryQuestions(from: questions)
        guard !retry.isEmpty else {
            feedback = SpeedFeedbackMessage(text: "本次全对，无需复练", success: nil)
            return
        }
        resetAttemptState()
        questions = retry
        index = 0
        currentInput = ""
        startedAt = .now
        questionStartedAt = .now
        screen = .practice
    }

    private func openDoodle() {
        guard !isSubmitting else { return }
        doodleController.prepareForPresentation()
        setDoodleVisible(true)
    }

    private func closeDoodle() {
        doodleController.showSettings = false
        setDoodleVisible(false)
    }

    private func setDoodleVisible(_ visible: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { showDoodle = visible }
    }

    private func doodleButton(_ symbol: String, _ label: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(active ? AppTheme.accent : Color.primary)
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func persistSettings() {
        try? SpeedRepository.saveSettings(settings, records: records, context: modelContext)
    }

    private func toggleFixedNumber(_ number: Int) {
        var values = selectedFixedNumbers
        if values.contains(number) {
            values.removeAll { $0 == number }
        } else {
            values.append(number)
            values.sort()
        }
        settings.customFixedNumbers = values
        persistSettings()
    }

    private func saveResultIfNeeded() {
        guard savedResultID == nil, !questions.isEmpty else { return }
        let id = UUID().uuidString
        let name = practiceTitle
        let record = SpeedRecord(id: id, date: .now, name: name, mode: settings.mode, totalTime: totalTime, correctCount: correctCount, totalCount: questions.count, details: questions)
        try? SpeedRepository.saveHistory([record] + history, records: records, context: modelContext)
        savedResultID = id
    }

    private func internalHeader(title: String, back: @escaping () -> Void) -> some View {
        HStack {
            Button(action: back) { Image(systemName: "chevron.left") }
                .frame(width: 40, height: 40)
            Spacer()
            Text(title).font(AppTheme.sectionTitleFont)
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
    }

    private func resultMetric(_ title: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.system(size: 20, weight: .semibold))
            Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 13))
    }

    private func errorText(for question: SpeedQuestion) -> String {
        guard let value = SpeedQuestionEngine.errorPercentage(input: question.input, answer: question.answer) else { return "误差 —" }
        return String(format: "误差 %.1f%%", value)
    }

    private func rating(for question: SpeedQuestion) -> SpeedRating {
        (question.type.ratingThresholds ?? .init(excellent: 18, good: 22, pass: 28)).rating(for: question.timeUsed)
    }

    private func ratingColor(for question: SpeedQuestion) -> Color {
        switch rating(for: question) {
        case .excellent: AppTheme.accent
        case .good: AppTheme.success
        case .pass: AppTheme.warning
        case .keepGoing: .secondary
        }
    }

    private func timeText(_ seconds: Double) -> String {
        String(format: "%02d:%02d", Int(seconds) / 60, Int(seconds) % 60)
    }
}

private struct SpeedKeyButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.93 : 1)
            .offset(y: configuration.isPressed ? 1 : 0)
            .brightness(configuration.isPressed ? 0.04 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.68), value: configuration.isPressed)
    }
}

private extension String {
    mutating func toggleSign() {
        if hasPrefix("-") { removeFirst() }
        else if !isEmpty { insert("-", at: startIndex) }
    }
}
