import SwiftData
import SwiftUI

struct HomeView: View {
    private enum DailyDeleteTarget: Identifiable {
        case todo(HomeTodo)
        case rule(HomeDailyTodoRule)

        var id: String {
            switch self {
            case let .todo(todo): "todo|\(todo.id)"
            case let .rule(rule): "rule|\(rule.id)"
            }
        }
    }

    private enum Editor: Equatable {
        case countdown(String?)
        case todo(String?)
        case dailyRules
        case dailyRule(String?)
        case sticky(String?)
    }

    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "todos"
            || record.collection == "daily_todo_rules"
            || record.collection == "stickies"
            || record.collection == "keyvalue"
    }) private var records: [StoredRecord]

    @State private var editor: Editor?
    @State private var inlineStickyID: String?
    @State private var inlineStickyText = ""
    @State private var showToast = false
    @State private var countdownNameDraft = ""
    @State private var countdownDateDraft = Date.now
    @State private var todoTitleDraft = ""
    @State private var todoNoteDraft = ""
    @State private var todoTypeDraft = "yanyu"
    @State private var todoScheduleDraft = Date.now
    @State private var todoRepeatsDailyDraft = false
    @State private var stickyContentDraft = ""
    @State private var stickyTagDraft = ""
    @State private var stickyColorDraft = "#FFFFFF"
    @State private var stickyPinnedDraft = false
    @State private var stickyFormatSelection = ""
    @State private var errorStats: HomeErrorStats?
    @State private var didRequestErrorStats = false
    @State private var saveErrorMessage: String?
    @State private var dailyDeleteTarget: DailyDeleteTarget?

    private var todos: [HomeTodo] { HomeRecordRepository.todos(from: records) }
    private var stickies: [HomeSticky] { HomeRecordRepository.stickies(from: records) }
    private var countdowns: [HomeCountdown] { HomeRecordRepository.countdowns(from: records) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                hero
                featureGrid
                todoSection
                stickySection
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 42)
        }
        .background(Color.white)
        .stableRootNavigationBar()
        .onAppear { NativePerformanceLog.event("home onAppear") }
        .task { await loadErrorStatsIfNeeded() }
        .task(id: scenePhase) { await maintainDailyTodoInstancesWhileActive() }
        .navigationDestination(for: AppRoute.self) { route in
            HomeShortcutView(route: route)
                .secondaryPageTabBarHidden()
        }
        .overlay { editorOverlay }
        .overlay(alignment: .top) {
            if showToast {
                NativeToast(message: "已保存")
                    .padding(.top, 12)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .alert("保存失败", isPresented: Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { saveErrorMessage = nil }
        } message: {
            Text(saveErrorMessage ?? "操作未完成，输入内容仍保留。")
        }
        .confirmationDialog("删除每日待办", isPresented: Binding(
            get: { dailyDeleteTarget != nil },
            set: { if !$0 { dailyDeleteTarget = nil } }
        ), titleVisibility: .visible) {
            if case let .some(.todo(todo)) = dailyDeleteTarget {
                Button("仅删除今天", role: .destructive) {
                    deleteDailyTodoForToday(todo)
                    dailyDeleteTarget = nil
                }
                if let rule = todo.dailyRuleID.flatMap({ id in dailyRules.first { $0.id == id } }) {
                    Button("删除每日规则并移除今天未完成项", role: .destructive) {
                        deleteDailyRule(rule.id)
                        dailyDeleteTarget = nil
                    }
                }
            } else if case let .some(.rule(rule)) = dailyDeleteTarget {
                Button("删除规则并移除今天未完成项", role: .destructive) {
                    deleteDailyRule(rule.id)
                    dailyDeleteTarget = nil
                }
            }
            Button("取消", role: .cancel) { dailyDeleteTarget = nil }
        } message: {
            if case .some(.todo(_)) = dailyDeleteTarget {
                Text("删除今天只会隐藏当天实例；删除规则会停止今后的自动生成，并保留已完成任务和历史记录。")
            } else {
                Text("会停止今后的自动生成；已完成任务和历史记录会保留。")
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("首页")
                .font(AppTheme.pageTitleFont)
                .accessibilityIdentifier("home-page-title")
            Text("\(greeting) · \(HomeRecordRepository.chineseDate(.now))")
                .font(AppTheme.auxiliaryFont)
                .foregroundStyle(.secondary)
        }
    }

    private var hero: some View {
        HStack(spacing: 0) {
            heroProgress
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(width: 0.7)
                .padding(.vertical, 2)
            countdownPanel
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(20)
        .frame(minHeight: heroMinimumHeight)
        .background(
            LinearGradient(
                colors: [Color(red: 0.88, green: 0.93, blue: 1.0), Color(red: 0.95, green: 0.975, blue: 1.0)],
                startPoint: .leading,
                endPoint: .trailing
            ),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(AppTheme.accent.opacity(0.15), lineWidth: 0.8)
        }
    }

    private var heroProgress: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("今日待办").font(.system(size: 14, weight: .semibold)).foregroundStyle(AppTheme.accent)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(completedTodayCount)")
                    .font(.system(size: 46, weight: .semibold, design: .rounded))
                Text("项已完成").font(.system(size: 14)).foregroundStyle(.secondary)
            }
            ProgressView(value: completionProgress).tint(AppTheme.accent).scaleEffect(x: 1, y: 1.35)
            Text("还有 \(unmasteredErrorCount) 道错题待掌握 · 本周新增 \(weekNewErrorCount) 道")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            if let running = todos.first(where: { $0.timerStartedAt != nil }) {
                timerCapsule(running)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.trailing, 20)
    }

    private var countdownPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("倒数日").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Button { beginCountdown(nil) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 18, weight: .semibold))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("新增倒数日")
            }

            if countdowns.isEmpty {
                Text("暂无倒数日").font(AppTheme.bodyFont).foregroundStyle(.secondary)
            } else {
                ForEach(countdowns.prefix(4)) { countdown in
                    HStack(spacing: 7) {
                        Button { beginCountdown(countdown) } label: {
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(countdown.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(countdownDateText(countdown)).font(.system(size: 10)).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 4)
                                Text(countdownRemainingText(countdown))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .foregroundStyle(AppTheme.accent)
                                    .monospacedDigit()
                            }
                        }
                        .buttonStyle(.plain)
                        Button { deleteCountdown(countdown.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除\(countdown.name)")
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 42)
                    .background(Color.white.opacity(0.88), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
        .padding(.leading, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func timerCapsule(_ todo: HomeTodo) -> some View {
        Button { toggleTimer(todo) } label: {
            HStack(spacing: 7) {
                Text(todo.title).lineLimit(1)
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(HomeRecordRepository.durationText(
                        milliseconds: todo.elapsedMilliseconds,
                        startedAt: todo.timerStartedAt,
                        now: context.date
                    ))
                    .monospacedDigit()
                }
                Image(systemName: "pause.fill")
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.accent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(AppTheme.accent.opacity(0.10), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var featureGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5), spacing: 10) {
            ForEach(HomeFeature.all) { feature in
                NavigationLink(value: feature.route) {
                    VStack(spacing: 8) {
                        Image(systemName: feature.systemImage)
                            .font(.system(size: 23, weight: .semibold))
                            .foregroundStyle(feature.color)
                            .frame(width: 56, height: 56)
                            .background(feature.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                        Text(feature.title)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(NativePressButtonStyle())
                .accessibilityIdentifier("home-shortcut-\(feature.id)")
            }
        }
    }

    private var todoSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("今日待办", systemImage: "checkmark.square")
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
                Text("\(todayTodos.filter { !$0.isCompleted && !$0.isSkipped }.count)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
                Spacer()
                Button { editor = .dailyRules } label: {
                    Image(systemName: "repeat.circle")
                        .font(.system(size: 19, weight: .semibold))
                }
                .accessibilityLabel("管理每日待办")
                Button { beginTodo(nil) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 19, weight: .semibold))
                }
                .accessibilityLabel("新增待办")
            }

            ProgressView(value: completionProgress)
                .tint(AppTheme.accent)
                .scaleEffect(x: 1, y: 1.18)

            if todayTodos.isEmpty {
                NativeStatusCard(
                    title: "还没有待办事项",
                    detail: "点击右上角新增，开启今日计划",
                    systemImage: "checkmark.square",
                    color: AppTheme.accent,
                    minimumHeight: 176
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(todayTodos) { todo in
                        HomeTodoRow(
                            todo: todo,
                            onToggleCompleted: { toggleCompleted(todo) },
                            onEdit: { beginTodo(todo) },
                            onSaveNote: { saveTodoNote(todo, note: $0) },
                            onLongPress: { beginTodo(todo) },
                            onDelete: { deleteTodo(todo.id) },
                            onSkipToday: { setDailyTodoSkipped(todo, skipped: !todo.isSkipped) },
                            onDeleteToday: { dailyDeleteTarget = .todo(todo) },
                            onDeleteRule: {
                                if let rule = todo.dailyRuleID.flatMap({ id in dailyRules.first { $0.id == id } }) {
                                    dailyDeleteTarget = .rule(rule)
                                }
                            },
                            onToggleTimer: { toggleTimer(todo) }
                        )
                        if todo.id != todayTodos.last?.id { Divider().padding(.leading, 42) }
                    }
                }
                .padding(.horizontal, 14)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(Color.primary.opacity(0.06), lineWidth: 0.6) }
            }
        }
    }

    private var stickySection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("便签", systemImage: "note.text")
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
                Text("\(stickies.count)").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                Spacer()
                Button { beginSticky(nil) } label: {
                    Image(systemName: "plus.circle.fill").font(.system(size: 19, weight: .semibold))
                }
                .accessibilityLabel("新增便签")
            }

            if stickies.isEmpty {
                NativeStatusCard(
                    title: "还没有便签",
                    detail: "点击右上角新增，写下第一条便签",
                    systemImage: "note.text",
                    color: AppTheme.accent,
                    minimumHeight: 176
                )
            } else {
                HStack(alignment: .top, spacing: 10) {
                    stickyColumn(even: true)
                    stickyColumn(even: false)
                }
            }
        }
    }

    private var heroMinimumHeight: CGFloat {
        switch countdowns.count {
        case 0: 150
        case 1: 166
        case 2: 198
        default: 228
        }
    }

    private func stickyColumn(even: Bool) -> some View {
        VStack(spacing: 10) {
            ForEach(Array(stickies.enumerated()).filter { $0.offset.isMultiple(of: 2) == even }, id: \.element.id) { _, sticky in
                HomeStickyCard(
                    sticky: sticky,
                    isInlineEditing: inlineStickyID == sticky.id,
                    inlineText: $inlineStickyText,
                    onBeginInlineEdit: {
                        inlineStickyID = sticky.id
                        inlineStickyText = sticky.content
                    },
                    onFinishInlineEdit: { finishInlineSticky(sticky) },
                    onOpenEditor: { beginSticky(sticky) },
                    onDelete: { deleteSticky(sticky.id) }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    @ViewBuilder
    private var editorOverlay: some View {
        switch editor {
        case .countdown(let id): countdownEditor(id: id)
        case .todo(let id): todoEditor(id: id)
        case .dailyRules: dailyRulesManager
        case .dailyRule(let id): dailyRuleEditor(id: id)
        case .sticky(let id): stickyEditor(id: id)
        case nil: EmptyView()
        }
    }

    private func countdownEditor(id: String?) -> some View {
        NativeEditorDialog(
            title: id == nil ? "新增倒数日" : "编辑倒数日",
            canSave: !countdownNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: closeEditor,
            onSave: saveCountdown
        ) {
            VStack(alignment: .leading, spacing: 12) {
                NativeFieldLabel(title: "名称")
                TextField("请输入倒数日名称", text: $countdownNameDraft).textFieldStyle(NativeTextFieldStyle())
                DatePicker("目标日期", selection: $countdownDateDraft, displayedComponents: .date)
                    .font(AppTheme.inputFont)
                    .environment(\.locale, Locale(identifier: "zh_CN"))
            }
        }
    }

    private func todoEditor(id: String?) -> some View {
        NativeEditorDialog(
            title: id == nil ? "新增待办" : "编辑待办",
            canSave: !todoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: closeEditor,
            onSave: saveTodo
        ) {
            VStack(alignment: .leading, spacing: 12) {
                NativeFieldLabel(title: "待办内容")
                TextField("准备完成什么？", text: $todoTitleDraft).textFieldStyle(NativeTextFieldStyle())
                if id == nil {
                    Toggle("每天重复", isOn: $todoRepeatsDailyDraft)
                        .font(AppTheme.inputFont)
                        .tint(AppTheme.accent)
                }
                if !todoRepeatsDailyDraft {
                    NativeFieldLabel(title: "备注")
                    TextEditor(text: $todoNoteDraft)
                        .modifier(NativeDirectionalTextFieldNavigation())
                        .font(AppTheme.inputFont)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(minHeight: 64, maxHeight: 88)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
                        .overlay { RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 0.6) }
                }
                DatePicker(todoRepeatsDailyDraft ? "开始日期" : "计划日期", selection: $todoScheduleDraft, displayedComponents: .date)
                DatePicker("计划时间", selection: $todoScheduleDraft, displayedComponents: .hourAndMinute)
                NativeFieldLabel(title: "科目")
                todoTypePicker
            }
            .font(AppTheme.inputFont)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }

    private var dailyRulesManager: some View {
        ZStack {
            Color.black.opacity(0.28).ignoresSafeArea().onTapGesture(perform: closeEditor)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("每日待办").font(AppTheme.sectionTitleFont)
                    Spacer()
                    Button("完成", action: closeEditor).font(.system(size: 14, weight: .medium))
                }

                Button { beginDailyRule(nil) } label: {
                    Label("新增每日待办", systemImage: "plus.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.accent)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                }

                if dailyRules.isEmpty {
                    NativeStatusCard(
                        title: "还没有每日待办",
                        detail: "创建后会从开始日期起每天自动加入今日待办",
                        systemImage: "repeat",
                        color: AppTheme.accent,
                        minimumHeight: 150
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 8) {
                            ForEach(dailyRules) { rule in
                                HomeDailyTodoRuleRow(
                                    rule: rule,
                                    onEdit: { beginDailyRule(rule) },
                                    onTogglePause: { setDailyRulePaused(rule, paused: !rule.isPaused) },
                                    onDelete: { dailyDeleteTarget = .rule(rule) }
                                )
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 440)
            .frame(maxHeight: 620)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .padding(24)
        }
        .transition(.opacity)
    }

    private func dailyRuleEditor(id: String?) -> some View {
        NativeEditorDialog(
            title: id == nil ? "新增每日待办" : "编辑每日待办",
            canSave: !todoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: closeEditor,
            onSave: saveDailyRule
        ) {
            VStack(alignment: .leading, spacing: 12) {
                NativeFieldLabel(title: "待办内容")
                TextField("准备每天完成什么？", text: $todoTitleDraft).textFieldStyle(NativeTextFieldStyle())
                DatePicker("开始日期", selection: $todoScheduleDraft, displayedComponents: .date)
                DatePicker("计划时间", selection: $todoScheduleDraft, displayedComponents: .hourAndMinute)
                NativeFieldLabel(title: "科目")
                todoTypePicker
            }
            .font(AppTheme.inputFont)
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }

    private var todoTypePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(HomeRecordRepository.todoTypes) { item in
                    Button(item.title) { todoTypeDraft = item.key }
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(todoTypeDraft == item.key ? .white : .primary)
                        .padding(.horizontal, 11)
                        .frame(height: 30)
                        .background(todoTypeDraft == item.key ? AppTheme.accent : Color.primary.opacity(0.055), in: Capsule())
                        .buttonStyle(.plain)
                }
            }
        }
    }

    private func stickyEditor(id: String?) -> some View {
        NativeEditorDialog(
            title: id == nil ? "新增便签" : "编辑便签",
            canSave: !stickyContentDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            onClose: closeEditor,
            onSave: saveSticky
        ) {
            VStack(alignment: .leading, spacing: 10) {
                NativeRichTextEditor(html: $stickyContentDraft, minHeight: 105, mode: .compact)
                Menu {
                    Button("无标签") { stickyTagDraft = "" }
                    ForEach(homeStickyTags) { item in Button(item.name) { stickyTagDraft = item.name } }
                } label: {
                    NativePropertyRow(title: "便签标签", value: stickyTagDraft.isEmpty ? "无标签" : stickyTagDraft, systemImage: "tag") {}
                        .allowsHitTesting(false)
                }
                HStack(spacing: 10) {
                    ForEach(HomeRecordRepository.stickyColors, id: \.self) { hex in
                        Button { stickyColorDraft = hex } label: {
                            Circle()
                                .fill(Color(homeHex: hex))
                                .frame(width: 26, height: 26)
                                .overlay { Circle().stroke(stickyColorDraft == hex ? AppTheme.accent : Color.primary.opacity(0.12), lineWidth: stickyColorDraft == hex ? 2.5 : 0.7) }
                                .overlay { if stickyColorDraft == hex { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(AppTheme.accent) } }
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                    Toggle("置顶", isOn: $stickyPinnedDraft).font(.system(size: 12, weight: .medium)).fixedSize()
                }
            }
        }
    }

    private var todayTodos: [HomeTodo] {
        todos.filter { todo in
            if todo.dailyRuleID != nil {
                guard let dailyDate = todo.dailyDate, Calendar.current.isDateInToday(dailyDate) else { return false }
                return true
            }
            if !todo.isCompleted { return true }
            guard let completedAt = todo.completedAt else { return false }
            return Calendar.current.isDateInToday(completedAt)
        }
    }

    private var dailyRules: [HomeDailyTodoRule] { HomeRecordRepository.dailyRules(from: records) }

    private var homeStickyTags: [StickyTagDefinition] {
        StickyTagRepository.tags(subject: "", module: "", records: records)
    }

    private var completedTodayCount: Int { todayTodos.filter(\.isCompleted).count }
    private var completionProgress: Double {
        let eligible = todayTodos.filter { !$0.isSkipped }
        guard !eligible.isEmpty else { return 0 }
        return Double(eligible.filter(\.isCompleted).count) / Double(eligible.count)
    }
    private var unmasteredErrorCount: Int {
        (errorStats ?? HomeErrorStatsRepository.cached(from: records) ?? .empty).unmastered
    }
    private var weekNewErrorCount: Int {
        (errorStats ?? HomeErrorStatsRepository.cached(from: records) ?? .empty).weekNew
    }

    @MainActor
    private func loadErrorStatsIfNeeded() async {
        guard !didRequestErrorStats else { return }
        didRequestErrorStats = true
        let started = ProcessInfo.processInfo.systemUptime
        if let cached = HomeErrorStatsRepository.cached(from: records) {
            errorStats = cached
            NativePerformanceLog.mark("home stats cache", since: started)
            return
        }
        errorStats = try? await HomeErrorStatsRepository.rebuild(in: modelContext.container)
        NativePerformanceLog.mark("home stats background rebuild", since: started)
    }
    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 0..<11: "早上好"
        case 11..<14: "中午好"
        case 14..<19: "下午好"
        default: "晚上好"
        }
    }

    private func beginCountdown(_ countdown: HomeCountdown?) {
        countdownNameDraft = countdown?.name ?? ""
        countdownDateDraft = countdown?.date ?? Calendar.current.date(byAdding: .day, value: 30, to: .now) ?? .now
        withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .countdown(countdown?.id) }
    }

    private func beginTodo(_ todo: HomeTodo?) {
        if let todo, let dailyRuleID = todo.dailyRuleID,
           let rule = dailyRules.first(where: { $0.id == dailyRuleID }) {
            beginDailyRule(rule)
            return
        }
        todoTitleDraft = todo?.title ?? ""
        todoNoteDraft = todo?.note ?? ""
        todoTypeDraft = todo?.type ?? "yanyu"
        todoScheduleDraft = todo?.scheduledAt ?? .now
        todoRepeatsDailyDraft = false
        withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .todo(todo?.id) }
    }

    private func beginDailyRule(_ rule: HomeDailyTodoRule?) {
        todoTitleDraft = rule?.title ?? ""
        todoNoteDraft = ""
        todoTypeDraft = rule?.type ?? "yanyu"
        todoScheduleDraft = rule.map { HomeDailyTodoPolicy.scheduledAt(on: $0.startDate, using: $0.scheduledTime) ?? $0.scheduledTime } ?? .now
        withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .dailyRule(rule?.id) }
    }

    private func beginSticky(_ sticky: HomeSticky?) {
        inlineStickyID = nil
        stickyContentDraft = sticky?.content ?? ""
        stickyTagDraft = sticky?.tag ?? ""
        stickyColorDraft = sticky?.colorHex ?? "#FFFFFF"
        stickyPinnedDraft = sticky?.isPinned ?? false
        stickyFormatSelection = ""
        withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .sticky(sticky?.id) }
    }

    private func closeEditor() { withAnimation(.easeOut(duration: 0.16)) { editor = nil } }

    private func saveCountdown() {
        guard case .countdown(let id) = editor else { return }
        let name = countdownNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var values = countdowns
        if let id, let index = values.firstIndex(where: { $0.id == id }) {
            values[index].name = name
            values[index].date = countdownDateDraft
        } else {
            values.append(HomeRecordRepository.makeCountdown(name: name, date: countdownDateDraft))
        }
        do { try HomeRecordRepository.save(countdowns: values, records: records, context: modelContext); completeSave() }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func saveTodo() {
        guard case .todo(let id) = editor else { return }
        let title = todoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if todoRepeatsDailyDraft {
            let rule = HomeRecordRepository.makeDailyRule(title: title, type: todoTypeDraft, startAndTime: todoScheduleDraft)
            do {
                try HomeRecordRepository.saveDailyRuleAndReconcileToday(rule: rule, context: modelContext)
                completeSave()
            } catch { saveErrorMessage = error.localizedDescription }
            return
        }
        var value = id.flatMap { key in todos.first(where: { $0.id == key }) }
            ?? HomeRecordRepository.makeTodo(title: title, note: "", type: todoTypeDraft, scheduledAt: todoScheduleDraft)
        value.title = title
        value.note = todoNoteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        value.type = todoTypeDraft
        value.scheduledAt = todoScheduleDraft
        do { try HomeRecordRepository.save(todo: value, records: records, context: modelContext); completeSave() }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func saveDailyRule() {
        guard case .dailyRule(let id) = editor else { return }
        let title = todoTitleDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        let prior = id.flatMap { key in dailyRules.first(where: { $0.id == key }) }
        var rule = HomeRecordRepository.makeDailyRule(title: title, type: todoTypeDraft, startAndTime: todoScheduleDraft, id: id)
        if let prior {
            rule.createdAt = prior.createdAt
            rule.isPaused = prior.isPaused
        }
        do {
            try HomeRecordRepository.saveDailyRuleAndReconcileToday(rule: rule, context: modelContext)
            withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .dailyRules }
            showSaveToast()
        } catch { saveErrorMessage = error.localizedDescription }
    }

    private func saveSticky() {
        guard case .sticky(let id) = editor else { return }
        let content = stickyContentDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        var value = id.flatMap { key in stickies.first(where: { $0.id == key }) }
            ?? HomeRecordRepository.makeSticky(content: content, tag: "", colorHex: stickyColorDraft, isPinned: stickyPinnedDraft)
        value.content = content
        value.tag = stickyTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        value.colorHex = stickyColorDraft
        value.isPinned = stickyPinnedDraft
        do { try HomeRecordRepository.save(sticky: value, records: records, context: modelContext); completeSave() }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func completeSave() {
        closeEditor()
        showSaveToast()
    }

    private func showSaveToast() {
        withAnimation(.spring(duration: 0.28, bounce: 0.12)) { showToast = true }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_200))
            withAnimation(.easeOut(duration: 0.2)) { showToast = false }
        }
    }

    private func deleteCountdown(_ id: String) {
        do { try HomeRecordRepository.save(countdowns: countdowns.filter { $0.id != id }, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func deleteTodo(_ id: String) {
        do { try HomeRecordRepository.remove(collection: "todos", id: id, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func deleteDailyTodoForToday(_ todo: HomeTodo) {
        do {
            try HomeRecordRepository.deleteDailyTodoForToday(todo, context: modelContext)
            showSaveToast()
        } catch { saveErrorMessage = error.localizedDescription }
    }

    private func setDailyTodoSkipped(_ todo: HomeTodo, skipped: Bool) {
        guard todo.dailyRuleID != nil else { return }
        var value = todo
        value.isSkipped = skipped
        if skipped { pauseTimer(&value) }
        do { try HomeRecordRepository.save(todo: value, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func setDailyRulePaused(_ rule: HomeDailyTodoRule, paused: Bool) {
        var value = rule
        value.isPaused = paused
        do {
            try HomeRecordRepository.save(rule: value, records: records, context: modelContext)
            try HomeRecordRepository.ensureDailyTodoInstances(context: modelContext)
        } catch { saveErrorMessage = error.localizedDescription }
    }

    private func deleteDailyRule(_ id: String) {
        do {
            try HomeRecordRepository.deleteDailyRule(id: id, context: modelContext)
            if editor == .dailyRules {
                withAnimation(.spring(duration: 0.25, bounce: 0.08)) { editor = .dailyRules }
            }
            showSaveToast()
        } catch { saveErrorMessage = error.localizedDescription }
    }

    @MainActor
    private func maintainDailyTodoInstancesWhileActive() async {
        guard scenePhase == .active else { return }
        refreshDailyTodoInstances()
        while !Task.isCancelled {
            var calendar = Calendar.current
            calendar.timeZone = .current
            let now = Date.now
            let nextMidnight = calendar.nextDate(
                after: now,
                matching: DateComponents(hour: 0, minute: 0, second: 0),
                matchingPolicy: .nextTime
            ) ?? (calendar.startOfDay(for: now).addingTimeInterval(86_400))
            let delay = max(1, nextMidnight.timeIntervalSince(now) + 1)
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled, scenePhase == .active else { return }
            refreshDailyTodoInstances()
        }
    }

    private func refreshDailyTodoInstances() {
        do { try HomeRecordRepository.ensureDailyTodoInstances(context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func deleteSticky(_ id: String) {
        if inlineStickyID == id { inlineStickyID = nil }
        do { try HomeRecordRepository.remove(collection: "stickies", id: id, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func toggleCompleted(_ todo: HomeTodo) {
        guard !todo.isSkipped else { return }
        var value = todo
        value.isCompleted.toggle()
        value.completedAt = value.isCompleted ? .now : nil
        if value.isCompleted { pauseTimer(&value) }
        do { try HomeRecordRepository.save(todo: value, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func saveTodoNote(_ todo: HomeTodo, note: String) {
        var value = todo
        value.note = note
        do { try HomeRecordRepository.save(todo: value, records: records, context: modelContext) }
        catch { saveErrorMessage = error.localizedDescription }
    }

    private func toggleTimer(_ todo: HomeTodo) {
        guard !todo.isCompleted, !todo.isSkipped else { return }
        var selected = todo
        do {
            if selected.timerStartedAt != nil {
                pauseTimer(&selected)
            } else {
                for running in todos where running.timerStartedAt != nil && running.id != selected.id {
                    var paused = running
                    pauseTimer(&paused)
                    try HomeRecordRepository.save(todo: paused, records: records, context: modelContext)
                }
                selected.timerStartedAt = .now
            }
            try HomeRecordRepository.save(todo: selected, records: records, context: modelContext)
        } catch { saveErrorMessage = error.localizedDescription }
    }

    private func pauseTimer(_ todo: inout HomeTodo) {
        guard let startedAt = todo.timerStartedAt else { return }
        let now = Date.now
        let end = todo.dailyDate.flatMap { dailyDate in
            HomeDailyTodoPolicy.elapsedThroughDailyMidnight(from: startedAt, dailyDate: dailyDate, now: now)
                .map { startedAt.addingTimeInterval($0) }
        } ?? now
        let milliseconds = max(0, end.timeIntervalSince(startedAt) * 1_000)
        todo.elapsedMilliseconds += milliseconds
        let day = todo.dailyDate.map(HomeRecordRepository.dayKey) ?? HomeRecordRepository.dayKey(startedAt)
        todo.dailyTimes[day, default: 0] += milliseconds
        todo.timerStartedAt = nil
    }

    private func finishInlineSticky(_ sticky: HomeSticky) {
        var value = sticky
        value.content = inlineStickyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.content.isEmpty { value.content = sticky.content }
        do {
            try HomeRecordRepository.save(sticky: value, records: records, context: modelContext)
            inlineStickyID = nil
        } catch { saveErrorMessage = error.localizedDescription }
    }

    private enum StickyFormat { case bold, outdent, indent, bullet, number }
    private func applyStickyFormat(_ format: StickyFormat) {
        switch format {
        case .bold:
            guard !stickyContentDraft.isEmpty else { return }
            stickyContentDraft = "**\(stickyContentDraft)**"
        case .indent:
            stickyContentDraft = stickyContentDraft.split(separator: "\n", omittingEmptySubsequences: false).map { "  " + String($0) }.joined(separator: "\n")
        case .outdent:
            stickyContentDraft = stickyContentDraft.split(separator: "\n", omittingEmptySubsequences: false).map { line in
                var value = String(line)
                if value.hasPrefix("  ") { value.removeFirst(2) }
                return value
            }.joined(separator: "\n")
        case .bullet:
            stickyContentDraft = stickyContentDraft.split(separator: "\n", omittingEmptySubsequences: false).map { "• " + String($0) }.joined(separator: "\n")
        case .number:
            stickyContentDraft = stickyContentDraft.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        }
    }

    private func stickyFormatButton(_ id: String, image: String, action: @escaping () -> Void) -> some View {
        Button {
            stickyFormatSelection = id
            action()
        } label: {
            Image(systemName: image)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(stickyFormatSelection == id ? AppTheme.accent : .primary)
                .frame(width: 36, height: 32)
                .background(stickyFormatSelection == id ? AppTheme.accent.opacity(0.11) : Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private func countdownDateText(_ countdown: HomeCountdown) -> String {
        let remaining = HomeRecordRepository.daysRemaining(until: countdown.date)
        if remaining == 0 { return "今天" }
        if remaining == 1 { return "明天" }
        return HomeRecordRepository.chineseDate(countdown.date, includeYear: false)
    }

    private func countdownRemainingText(_ countdown: HomeCountdown) -> String {
        let remaining = HomeRecordRepository.daysRemaining(until: countdown.date)
        if remaining == 0 { return "今天" }
        if remaining < 0 { return "已过" }
        return "\(remaining) 天"
    }
}
