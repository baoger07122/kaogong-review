import AudioToolbox
import SwiftData
import SwiftUI
import UIKit

struct SpeedPracticeView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var records: [StoredRecord]
    @State private var screen: SpeedScreen = .home
    @State private var settings = SpeedSettings()
    @State private var estimateRows: [SpeedEstimateRow] = []
    @State private var questions: [SpeedQuestion] = []
    @State private var index = 0
    @State private var currentInput = ""
    @State private var startedAt = Date()
    @State private var questionStartedAt = Date()
    @State private var selectedHistory: SpeedRecord?
    @State private var savedResultID: String?
    @State private var showAnswer = false
    @State private var didLoad = false

    private var history: [SpeedRecord] { SpeedRepository.history(from: records).sorted { $0.date > $1.date } }

    var body: some View {
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
        .background(settings.nightMode ? Color.black : Color.white)
        .foregroundStyle(settings.nightMode ? Color.white : Color.primary)
        .navigationTitle("速算练习")
        .navigationBarTitleDisplayMode(.inline)
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
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 9) {
                    speedActionChip("历史", image: "clock.arrow.circlepath") { screen = .history }
                    speedActionChip("统计", image: "chart.bar.fill") { screen = .statistics }
                    speedActionChip("估算表", image: "tablecells") { screen = .estimateTable }
                    Spacer()
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle").font(.system(size: 12, weight: .semibold))
                        Text("确定")
                        Toggle("", isOn: settingBinding(\.confirmAuto)).labelsHidden().controlSize(.small)
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 36)
                    .background(Color.primary.opacity(0.05), in: Capsule())
                }

                speedModuleCard(
                    title: "基础计算",
                    image: "abacus",
                    values: SpeedTypeKey.allCases.filter { !$0.isDataAnalysis }
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

                DisclosureGroup("练习设置") {
                    VStack(spacing: 10) {
                        customTypes
                        settingsCard
                    }
                    .padding(.top, 10)
                }
                .font(AppTheme.inputFont)
                .padding(.horizontal, 15)
                .padding(.vertical, 12)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.06), lineWidth: 0.7) }

                Button(startButtonTitle) { start() }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(canStart ? AppTheme.accent : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .buttonStyle(NativePressButtonStyle())
                    .disabled(!canStart)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func typeGrid(_ values: [SpeedTypeKey]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(values) { type in
                Button {
                    settings.selectedType = type
                    if type.isAvailable { settings.customTypes = [type] }
                    persistSettings()
                } label: {
                    HStack(spacing: 9) {
                        Text(typeSymbol(type))
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                            .foregroundStyle(settings.selectedType == type ? Color.white : AppTheme.accent)
                            .frame(width: 36, height: 36)
                            .background(
                                settings.selectedType == type ? AppTheme.accent : AppTheme.accent.opacity(0.09),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                            )
                        VStack(alignment: .leading, spacing: 3) {
                            Text(type.name).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.82)
                            Text(typeSubtitle(type))
                                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(
                        settings.selectedType == type ? AppTheme.accent.opacity(0.10) : Color(red: 0.973, green: 0.98, blue: 1),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(settings.selectedType == type ? AppTheme.accent : AppTheme.accent.opacity(0.16), lineWidth: settings.selectedType == type ? 1.2 : 0.7)
                    }
                    .shadow(color: settings.selectedType == type ? AppTheme.accent.opacity(0.18) : .clear, radius: 6, y: 2)
                }
                .buttonStyle(.plain)
                .disabled(!type.isAvailable)
            }
        }
    }

    private func speedModuleCard(title: String, image: String, values: [SpeedTypeKey]) -> some View {
        VStack(alignment: .leading, spacing: 11) {
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
            typeGrid(values)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.055), lineWidth: 0.7) }
    }

    private func speedActionChip(_ title: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: image)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(Color.primary.opacity(0.05), in: Capsule())
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

    private var customTypes: some View {
        DisclosureGroup("自定义练习 · 可多选题型") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 7)], spacing: 7) {
                ForEach(SpeedTypeKey.allCases.filter(\.isAvailable)) { type in
                    Button {
                        if settings.customTypes.contains(type) {
                            settings.customTypes.removeAll { $0 == type }
                        } else {
                            settings.customTypes.append(type)
                        }
                        persistSettings()
                    } label: {
                        Label(type.name, systemImage: settings.customTypes.contains(type) ? "checkmark.circle.fill" : "circle")
                            .font(AppTheme.auxiliaryFont)
                            .foregroundStyle(settings.customTypes.contains(type) ? AppTheme.accent : Color.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 10)

            Divider().padding(.vertical, 8)
            HStack {
                Text("数字设置").font(AppTheme.bodyFont)
                Spacer()
                Picker("数字设置", selection: customNumberModeBinding) {
                    ForEach(SpeedCustomNumberMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
            }

            switch settings.customNumberMode ?? .none {
            case .none:
                Text("保持题型原有数字规则")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            case .fixed:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 7), count: 9), spacing: 7) {
                    ForEach(1...9, id: \.self) { number in
                        Button {
                            toggleFixedNumber(number)
                        } label: {
                            Text("\(number)")
                                .font(AppTheme.inputFont.monospacedDigit())
                                .frame(maxWidth: .infinity, minHeight: 32)
                                .background(
                                    selectedFixedNumbers.contains(number) ? AppTheme.accent.opacity(0.14) : AppTheme.secondaryBackground,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(selectedFixedNumbers.contains(number) ? AppTheme.accent : Color.clear, lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                    }
                }
            case .range:
                HStack(spacing: 8) {
                    TextField("最小值", value: customRangeMinimumBinding, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(NativeTextFieldStyle())
                    Text("至").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    TextField("最大值", value: customRangeMaximumBinding, format: .number)
                        .keyboardType(.numberPad)
                        .textFieldStyle(NativeTextFieldStyle())
                }
                Text("范围限制为 1–999；只替换纯四则运算的第二个数字。")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
        .font(AppTheme.bodyFont)
        .padding(14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("使用屏幕数字键盘", isOn: settingBinding(\.useScreenKeyboard))
            Toggle("按所选题型顺序出题", isOn: settingBinding(\.sequential))
            Toggle("夜间模式", isOn: settingBinding(\.nightMode))
            Toggle("结果不出现负数", isOn: settingBinding(\.noNegative))
            Toggle("显示快速备注", isOn: settingBinding(\.quickMemo))
            Toggle("按键音效", isOn: soundEnabledBinding)
        }
        .font(AppTheme.inputFont)
        .padding(15)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var practice: some View {
        VStack(spacing: 0) {
            internalHeader(title: "第 \(index + 1) / \(questions.count) 题", back: { abandon() })
            if questions.indices.contains(index) {
                let question = questions[index]
                VStack(spacing: 18) {
                    ProgressView(value: Double(index), total: Double(max(1, questions.count)))
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(timeText(context.date.timeIntervalSince(startedAt)))
                            .font(AppTheme.auxiliaryFont.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Text(question.type.name).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.accent)
                    Text(question.expression)
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: 82)

                    HStack {
                        Text(currentInput.isEmpty ? "请输入答案" : currentInput)
                            .font(.system(size: 26, weight: .medium, design: .monospaced))
                            .foregroundStyle(currentInput.isEmpty ? Color.secondary : Color.primary)
                        Spacer()
                        Button { showAnswer.toggle() } label: { Image(systemName: showAnswer ? "eye.slash" : "eye") }
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 56)
                    .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius))

                    if showAnswer {
                        Text("参考答案：\(SpeedQuestionEngine.answerText(question.answer))")
                            .font(AppTheme.bodyFont).foregroundStyle(AppTheme.warning)
                    }

                    if settings.quickMemo {
                        TextField("快速备注（可选）", text: memoBinding)
                            .textFieldStyle(NativeTextFieldStyle())
                    }

                    if settings.useScreenKeyboard {
                        numberPad
                    } else {
                        TextField("答案", text: $currentInput)
                            .keyboardType(.decimalPad)
                            .textFieldStyle(NativeTextFieldStyle())
                    }

                    Button("确认答案") { submit() }
                        .buttonStyle(NativePrimaryButtonStyle())
                        .disabled(Double(currentInput) == nil)
                }
                .padding(20)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var numberPad: some View {
        let keys = ["7", "8", "9", "4", "5", "6", "1", "2", "3", ".", "0", "⌫"]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3), spacing: 8) {
            ForEach(keys, id: \.self) { key in
                Button { pressKey(key) } label: {
                    Text(key).font(.system(size: 20, weight: .medium, design: .rounded))
                        .frame(maxWidth: .infinity).frame(height: 46)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(NativePressButtonStyle())
            }
            Button { currentInput.toggleSign() } label: {
                Text("±").frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(NativeSecondaryButtonStyle())
            Button { currentInput = "" } label: {
                Text("清空").frame(maxWidth: .infinity).frame(height: 42)
            }
            .buttonStyle(NativeSecondaryButtonStyle())
        }
    }

    private var result: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(AppTheme.accent)
                Text("本轮练习完成").font(AppTheme.pageTitleFont)
                Text(resultStandardText)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 10) {
                    resultMetric("正确", value: "\(correctCount)/\(questions.count)")
                    resultMetric("正确率", value: questions.isEmpty ? "0%" : "\(Int(Double(correctCount) / Double(questions.count) * 100))%")
                    resultMetric("用时", value: timeText(totalTime))
                }
                VStack(spacing: 8) {
                    ForEach(questions) { question in
                        HStack {
                            Image(systemName: question.isCorrect == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundStyle(question.isCorrect == true ? AppTheme.success : AppTheme.danger)
                            Text(question.expression).font(AppTheme.bodyFont)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 3) {
                                Text("\(question.input) / \(SpeedQuestionEngine.answerText(question.answer))")
                                    .font(AppTheme.auxiliaryFont.monospacedDigit()).foregroundStyle(.secondary)
                                HStack(spacing: 7) {
                                    Text(errorText(for: question))
                                    Text(String(format: "%.1fs", question.timeUsed))
                                    Text(rating(for: question).rawValue)
                                        .foregroundStyle(ratingColor(for: question))
                                }
                                .font(AppTheme.auxiliaryFont.monospacedDigit())
                            }
                        }
                        .padding(12)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                HStack(spacing: 10) {
                    Button("再练一次") { start() }.buttonStyle(NativePrimaryButtonStyle())
                    Button("返回题型") { screen = .home }.buttonStyle(NativeSecondaryButtonStyle())
                }
            }
            .padding(20)
        }
        .task { saveResultIfNeeded() }
    }

    private var historyView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                internalHeader(title: selectedHistory == nil ? "历史记录" : "练习回看", back: {
                    if selectedHistory != nil { selectedHistory = nil } else { screen = .home }
                })
                if let record = selectedHistory {
                    Text("\(record.name) · \(record.date.formatted(.dateTime.year().month().day().hour().minute()))")
                        .font(AppTheme.bodyFont).foregroundStyle(.secondary)
                    ForEach(record.details) { question in
                        HStack {
                            Text(question.expression).font(AppTheme.bodyFont)
                            Spacer()
                            Text("\(question.input) / \(SpeedQuestionEngine.answerText(question.answer))")
                                .font(AppTheme.auxiliaryFont.monospacedDigit())
                        }
                        .padding(12)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                } else if history.isEmpty {
                    NativeStatusCard(title: "暂无练习历史", detail: "完成一轮练习后自动保存", systemImage: "clock", color: AppTheme.accent)
                } else {
                    ForEach(history) { record in
                        Button { selectedHistory = record } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.name).font(AppTheme.cardTitleFont)
                                    Text(record.date.formatted(.dateTime.year().month().day().hour().minute()))
                                        .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(record.correctCount)/\(record.totalCount)").font(AppTheme.inputFont.weight(.semibold))
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                            .padding(14)
                            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                    }
                    Button("清除全部历史") { try? SpeedRepository.saveHistory([], records: records, context: modelContext) }
                        .buttonStyle(NativeDangerButtonStyle())
                }
            }
            .padding(20)
        }
    }

    private var statistics: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                internalHeader(title: "练习统计", back: { screen = .home })
                HStack(spacing: 10) {
                    resultMetric("练习次数", value: "\(history.count)")
                    resultMetric("累计题数", value: "\(history.reduce(0) { $0 + $1.totalCount })")
                    let total = history.reduce(0) { $0 + $1.totalCount }
                    let correct = history.reduce(0) { $0 + $1.correctCount }
                    resultMetric("总正确率", value: total == 0 ? "0%" : "\(Int(Double(correct) / Double(total) * 100))%")
                }
                ForEach(SpeedTypeKey.allCases.filter(\.isAvailable)) { type in
                    let matching = history.flatMap(\.details).filter { $0.type == type }
                    if !matching.isEmpty {
                        HStack {
                            Text(type.name).font(AppTheme.bodyFont)
                            Spacer()
                            Text("\(matching.filter { $0.isCorrect == true }.count)/\(matching.count)")
                                .font(AppTheme.inputFont.weight(.semibold))
                        }
                        .padding(13)
                        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
            }
            .padding(20)
        }
    }

    private var estimateTable: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                internalHeader(title: "估算表", back: { screen = .home })
                HStack {
                    Text("范围 → 估算值").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button { estimateRows.append(.init(id: UUID().uuidString, minimum: 100, maximum: 199, value: 100)) } label: { Label("新增", systemImage: "plus") }
                }
                ForEach($estimateRows) { $row in
                    HStack(spacing: 8) {
                        TextField("最小", value: $row.minimum, format: .number).textFieldStyle(NativeTextFieldStyle())
                        Text("—")
                        TextField("最大", value: $row.maximum, format: .number).textFieldStyle(NativeTextFieldStyle())
                        Image(systemName: "arrow.right")
                        TextField("估算值", value: $row.value, format: .number).textFieldStyle(NativeTextFieldStyle())
                        Button(role: .destructive) { estimateRows.removeAll { $0.id == row.id } } label: { Image(systemName: "trash") }
                    }
                }
                Button("保存估算表") {
                    try? SpeedRepository.saveEstimateRows(estimateRows, records: records, context: modelContext)
                }
                .buttonStyle(NativePrimaryButtonStyle())
            }
            .padding(20)
        }
    }

    private var activeTypes: [SpeedTypeKey] {
        let custom = settings.customTypes.filter(\.isAvailable)
        return custom.count > 1 ? custom : (settings.selectedType.isAvailable ? [settings.selectedType] : [])
    }

    private var canStart: Bool {
        guard settings.selectedType != .dataReal, !activeTypes.isEmpty else { return false }
        if settings.customNumberMode == .fixed { return !selectedFixedNumbers.isEmpty }
        return true
    }

    private var startButtonTitle: String {
        if settings.selectedType == .dataReal { return "该题型尚未开放" }
        if settings.customNumberMode == .fixed, selectedFixedNumbers.isEmpty { return "请先选择固定数字" }
        return "开始练习"
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
        (settings.customFixedNumbers ?? []).filter { (1...9).contains($0) }
    }

    private var correctCount: Int { questions.filter { $0.isCorrect == true }.count }
    private var totalTime: Double { questions.reduce(0) { $0 + $1.timeUsed } }

    private var resultStandardText: String {
        let fallback = SpeedRatingThresholds(excellent: 18, good: 22, pass: 28)
        let firstType = questions.first?.type
        let usesSingleType = firstType.map { type in questions.allSatisfy { $0.type == type } } ?? false
        let thresholds = usesSingleType ? firstType?.ratingThresholds ?? fallback : fallback
        return "误差 ±3%　合格 ≤ \(Int(thresholds.pass))s　良好 ≤ \(Int(thresholds.good))s　优秀 ≤ \(Int(thresholds.excellent))s"
    }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<SpeedSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; persistSettings() })
    }

    private func start() {
        let generated = SpeedQuestionEngine.questions(
            types: activeTypes,
            count: settings.questionCount,
            sequential: settings.sequential,
            estimates: estimateRows,
            customMode: settings.customNumberMode,
            fixedNumbers: selectedFixedNumbers,
            rangeMinimum: settings.customRangeMinimum ?? 1,
            rangeMaximum: settings.customRangeMaximum ?? 99
        )
        guard !generated.isEmpty else { return }
        questions = generated
        index = 0
        currentInput = ""
        startedAt = .now
        questionStartedAt = .now
        savedResultID = nil
        showAnswer = false
        screen = .practice
    }

    private func submit() {
        guard questions.indices.contains(index), !currentInput.isEmpty else { return }
        questions[index].input = currentInput
        questions[index].timeUsed = Date.now.timeIntervalSince(questionStartedAt)
        questions[index].isCorrect = SpeedQuestionEngine.isCorrect(input: currentInput, answer: questions[index].answer, type: questions[index].type)
        let success = questions[index].isCorrect == true
        UINotificationFeedbackGenerator().notificationOccurred(success ? .success : .error)
        if settings.confirmAuto {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { advance() }
        } else {
            advance()
        }
    }

    private func advance() {
        if index + 1 >= questions.count {
            screen = .result
        } else {
            index += 1
            currentInput = ""
            questionStartedAt = .now
            showAnswer = false
        }
    }

    private func abandon() {
        questions = []
        currentInput = ""
        screen = .home
    }

    private func pressKey(_ key: String) {
        if settings.soundEnabled != false { AudioServicesPlaySystemSound(1104) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if key == "⌫" { if !currentInput.isEmpty { currentInput.removeLast() } }
        else if key == "." { if !currentInput.contains(".") { currentInput += currentInput.isEmpty ? "0." : "." } }
        else if currentInput.count < 12 { currentInput += key }
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
        let name = activeTypes.count > 1 ? "自定义练习" : (questions.first?.type.name ?? "速算练习")
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

private extension String {
    mutating func toggleSign() {
        if hasPrefix("-") { removeFirst() }
        else if !isEmpty { insert("-", at: startIndex) }
    }
}
