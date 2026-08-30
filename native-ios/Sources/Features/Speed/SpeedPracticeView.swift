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
            estimateRows = SpeedRepository.estimateRows(from: records)
        }
    }

    private var home: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    Button { screen = .history } label: { Label("历史", systemImage: "clock.arrow.circlepath") }
                    Button { screen = .statistics } label: { Label("统计", systemImage: "chart.bar") }
                    Button { screen = .estimateTable } label: { Label("估算表", systemImage: "tablecells") }
                    Spacer()
                }
                .font(AppTheme.inputFont.weight(.semibold))

                Picker("模式", selection: settingBinding(\.mode)) {
                    ForEach(SpeedMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                Text("基础计算").font(AppTheme.sectionTitleFont)
                typeGrid(SpeedTypeKey.allCases.filter { !$0.isDataAnalysis })
                Text("资料分析").font(AppTheme.sectionTitleFont)
                typeGrid(SpeedTypeKey.allCases.filter(\.isDataAnalysis))

                customTypes
                settingsCard

                Button(settings.selectedType == .dataReal ? "该题型尚未开放" : "开始练习") { start() }
                    .buttonStyle(NativePrimaryButtonStyle())
                    .disabled(settings.selectedType == .dataReal || activeTypes.isEmpty)
            }
            .padding(20)
        }
    }

    private func typeGrid(_ values: [SpeedTypeKey]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 128), spacing: 9)], spacing: 9) {
            ForEach(values) { type in
                Button {
                    settings.selectedType = type
                    if type.isAvailable { settings.customTypes = [type] }
                    persistSettings()
                } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(type.name).font(AppTheme.cardTitleFont).lineLimit(1)
                        Text(type.isAvailable ? "点击选择" : "网页版暂未实现")
                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                    .background(
                        settings.selectedType == type ? AppTheme.accent.opacity(0.12) : AppTheme.secondaryBackground,
                        in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                            .stroke(settings.selectedType == type ? AppTheme.accent : Color.clear, lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!type.isAvailable)
            }
        }
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
        }
        .font(AppTheme.bodyFont)
        .padding(14)
        .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("题目数量").font(AppTheme.bodyFont)
                Spacer()
                Stepper("\(settings.questionCount) 题", value: settingBinding(\.questionCount), in: 5...50, step: 5)
                    .labelsHidden()
                Text("\(settings.questionCount) 题").font(AppTheme.inputFont.monospacedDigit())
            }
            Toggle("答题后自动进入下一题", isOn: settingBinding(\.confirmAuto))
            Toggle("使用屏幕数字键盘", isOn: settingBinding(\.useScreenKeyboard))
            Toggle("按所选题型顺序出题", isOn: settingBinding(\.sequential))
            Toggle("夜间模式", isOn: settingBinding(\.nightMode))
            Toggle("结果不出现负数", isOn: settingBinding(\.noNegative))
            Toggle("显示快速备注", isOn: settingBinding(\.quickMemo))
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
                            Text("\(question.input) / \(SpeedQuestionEngine.answerText(question.answer))")
                                .font(AppTheme.auxiliaryFont.monospacedDigit()).foregroundStyle(.secondary)
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

    private var memoBinding: Binding<String> {
        Binding(get: { questions.indices.contains(index) ? questions[index].memo : "" }, set: { if questions.indices.contains(index) { questions[index].memo = $0 } })
    }

    private var correctCount: Int { questions.filter { $0.isCorrect == true }.count }
    private var totalTime: Double { questions.reduce(0) { $0 + $1.timeUsed } }

    private func settingBinding<Value>(_ keyPath: WritableKeyPath<SpeedSettings, Value>) -> Binding<Value> {
        Binding(get: { settings[keyPath: keyPath] }, set: { settings[keyPath: keyPath] = $0; persistSettings() })
    }

    private func start() {
        let generated = SpeedQuestionEngine.questions(types: activeTypes, count: settings.questionCount, sequential: settings.sequential, estimates: estimateRows)
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
        AudioServicesPlaySystemSound(1104)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if key == "⌫" { if !currentInput.isEmpty { currentInput.removeLast() } }
        else if key == "." { if !currentInput.contains(".") { currentInput += currentInput.isEmpty ? "0." : "." } }
        else if currentInput.count < 12 { currentInput += key }
    }

    private func persistSettings() {
        try? SpeedRepository.saveSettings(settings, records: records, context: modelContext)
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
