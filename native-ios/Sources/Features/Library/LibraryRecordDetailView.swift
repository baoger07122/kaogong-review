import Foundation
import SwiftData
import SwiftUI
import UIKit

struct LibraryRecordDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var doodleSession: LibraryDoodleSession
    @Query(filter: #Predicate<StoredRecord> { record in record.collection == "words" || record.collection == "errors" }) private var records: [StoredRecord]
    let kind: LibraryContentKind
    let scope: LibraryScope
    let record: StoredRecord?
    let questionBankContext: QuestionBankQuestionAnalysisContext?
    let onEdit: () -> Void
    let onDelete: () -> Void
    var onClearAnswer: (() -> Void)? = nil
    var onDone: (() -> Void)? = nil
    var onOpenLinkedWord: ((String) -> Void)? = nil

    @State private var object: [String: Any]

    @State private var showDelete = false
    @State private var showClearAnswer = false
    @State private var showQuestionBankEditor = false
    @StateObject private var noteSession = LibraryInlineNoteSession()
    @State private var expandedQuestionSourceID: String?
    @State private var showWordSelection = false
    @State private var linkedWordCreationCategory: WordCategory?
    @State private var linkedWordDetailTarget: LinkedWordDetailTarget?
    @State private var linkedQuestionBankContext: QuestionBankQuestionAnalysisContext?

    init(
        kind: LibraryContentKind,
        scope: LibraryScope,
        record: StoredRecord,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onOpenLinkedWord: ((String) -> Void)? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.record = record
        questionBankContext = nil
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.onOpenLinkedWord = onOpenLinkedWord
        _object = State(initialValue: record.jsonObject ?? [:])
    }

    init(
        questionBankContext: QuestionBankQuestionAnalysisContext,
        onEdit: @escaping () -> Void,
        onClearAnswer: @escaping () -> Void,
        onDone: @escaping () -> Void,
        onOpenLinkedWord: ((String) -> Void)? = nil
    ) {
        let mapping = questionBankContext.typeMapping
        kind = .errors
        scope = LibraryScope(subject: mapping.subject, module: mapping.module)
        record = nil
        self.questionBankContext = questionBankContext
        self.onEdit = onEdit
        onDelete = {}
        self.onClearAnswer = onClearAnswer
        self.onDone = onDone
        self.onOpenLinkedWord = onOpenLinkedWord
        _object = State(initialValue: questionBankContext.detailObject)
    }

    var body: some View {
        detailBehavior
    }

    private var detailBehavior: some View {
        detailStateTracking
            .task(id: linkedQuestionContextKey) { loadLinkedQuestionContext() }
            .overlay {
                if questionBankContext != nil {
                    QuestionBankDoodleAutosaveObserver(session: doodleSession, context: modelContext)
                }
            }
            .confirmationDialog("清除本题作答记录？", isPresented: $showClearAnswer, titleVisibility: .visible) {
                Button("清除本题作答记录", role: .destructive) { onClearAnswer?() }
                Button("取消", role: .cancel) {}
            } message: {
                Text("将清除本题已选选项和答案揭示状态，题目、笔记和涂鸦会保留。")
            }
    }

    private var detailStateTracking: some View {
        detailNavigationDestination
            .onChange(of: record?.updatedAt) { _, _ in
                if let record { object = record.jsonObject ?? [:] }
            }
            .onChange(of: questionBankContext?.record.payload) { _, _ in
                if let questionBankContext { object = questionBankContext.detailObject }
            }
            .onChange(of: questionBankContext?.answerStateKey) { _, _ in
                if let questionBankContext { object = questionBankContext.detailObject }
            }
            .onChange(of: questionSourceIdentity) { _, _ in
                expandedQuestionSourceID = nil
            }
    }

    private var detailNavigationDestination: some View {
        detailSheets
            .navigationDestination(item: $linkedWordDetailTarget) { target in
                if let word = records.first(where: { $0.collection == "words" && $0.recordID == target.recordID }) {
                    WordLibraryRecordDetailView(record: word)
                }
            }
    }

    private var detailSheets: some View {
        detailToolbarContainer
            .sheet(item: $linkedWordCreationCategory) { category in
                NavigationStack {
                    LibraryRecordEditorView(
                        kind: .words,
                        scope: LibraryScope(subject: "言语理解", module: "逻辑填空"),
                        preferredType: category.rawValue,
                        onSaved: linkNewWord
                    )
                }
            }
            .sheet(isPresented: $showQuestionBankEditor) {
            if AppFeatureAvailability.questionBank, let questionBankContext {
                NavigationStack {
                    LibraryRecordEditorView(
                        questionBankContext: questionBankContext,
                        onQuestionBankAnalysisSaved: {
                            object = questionBankContext.detailObject
                            showQuestionBankEditor = false
                        }
                    )
                }
                }
            }
    }

    private var detailToolbarContainer: some View {
        detailNavigationContainer
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    detailToolbar
                }
                .documentToolbarBackground()
            }
    }

    private var detailNavigationContainer: some View {
        detailContent
            .navigationTitle(detailNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .background(NativeNavigationInteraction(blocked: doodleSession.isPresented))
            .toolbar(.visible, for: .navigationBar)
            .onAppear { logQuestionBankDetailLifecycle("navigation-root-appear") }
    }

    private var detailNavigationTitle: String {
        guard let questionBankContext else { return "错题详情" }
        return "第\(questionBankContext.question.number)题详情"
    }

    private var detailContent: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
            ZStack {
                detailScrollView(availableWidth: availableWidth)
                detailModal
            }
        }
    }

    private func detailScrollView(availableWidth: CGFloat) -> some View {
        let readingColumnWidth = min(availableWidth.isFinite ? max(0, availableWidth) : 0, 920)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metadata
                questionBankMaterialBlock
                questionBlock
                imagesBlock(availableWidth: max(0, readingColumnWidth - 32))
                optionsBlock
                answerAndSource
                explanationBlock
                comparisonBlock
                linkedErrorBlock
                reviewBlock
                noteBlock
                dateBlock
            }
            .padding(.horizontal, 16)
            .padding(.top, 5)
            .padding(.bottom, 14)
            .frame(width: readingColumnWidth, alignment: .leading)
            .overlay {
                LibraryDoodleContentLayer(
                    session: doodleSession,
                    targetRecordID: activeRecordID
                )
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Color.white)
        .accessibilityIdentifier(questionBankContext.map {
            "question-bank-detail-scroll-\($0.question.id)"
        } ?? "library-record-detail-scroll")
        .onAppear { logQuestionBankDetailLifecycle("scroll-appear") }
        .onDisappear { logQuestionBankDetailLifecycle("scroll-disappear") }
    }

    @ViewBuilder
    private var detailModal: some View {
        if showDelete {
            NativeDeleteDialog(
                title: "删除错题",
                message: "删除后无法在 App 内恢复。",
                onDelete: { showDelete = false; onDelete() },
                onCancel: { showDelete = false }
            )
        } else if showWordSelection {
            LibraryRelationSelectionDialog(
                collection: "words",
                candidates: records,
                selection: linkedWordSelection,
                onClose: { showWordSelection = false },
                onCreateWord: { category in
                    showWordSelection = false
                    linkedWordCreationCategory = category
                }
            )
        }
    }

    private var detailToolbar: some View {
        HStack(spacing: 8) {
            detailToolbarActions
        }
        .frame(minHeight: 44)
        .id(doodleSession.isPresented ? "record-toolbar-doodle" : "record-toolbar-detail")
    }

    @ViewBuilder
    private var detailToolbarActions: some View {
        if questionBankContext != nil && !AppFeatureAvailability.questionBank {
            toolbarPlaceholder
            toolbarPlaceholder
        } else if doodleSession.isPresented {
            toolbarPlaceholder
            toolbarPlaceholder
        } else {
            Button(action: openDoodle) { Image(systemName: "pencil.and.scribble") }
                .accessibilityLabel("涂鸦")
            questionActionsMenu
        }
        if let onDone, questionBankContext != nil, AppFeatureAvailability.questionBank {
            Button("完成") {
                noteSession.finish { saved in
                    if saved { onDone() }
                }
            }
                .disabled(doodleSession.isPresented)
                .accessibilityIdentifier("question-bank-detail-done")
        }
    }

    private var toolbarPlaceholder: some View {
        Color.clear
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var questionActionsMenu: some View {
        Menu {
            if questionBankContext == nil {
                Button {
                    noteSession.finish { saved in
                        if saved { onEdit() }
                    }
                } label: {
                    Label("编辑错题", systemImage: "pencil")
                }
            } else {
                Button {
                    noteSession.finish { saved in
                        if saved { showQuestionBankEditor = true }
                    }
                } label: {
                    Label("编辑题目", systemImage: "pencil")
                }
                .accessibilityIdentifier("question-bank-edit-question")
            }
            if questionBankContext != nil {
                Button {
                    noteSession.finish { saved in
                        if saved { showClearAnswer = true }
                    }
                } label: {
                    Label("清除本题作答记录", systemImage: "arrow.counterclockwise")
                }
                .accessibilityIdentifier("question-bank-clear-question-answer")
            } else {
                Button(role: .destructive) {
                    noteSession.finish { saved in
                        if saved { showDelete = true }
                    }
                } label: {
                    Label("删除错题", systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("题目操作")
        .accessibilityIdentifier("question-bank-question-actions")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let questionBankContext {
                HStack(spacing: 6) {
                    if questionBankContext.currentQuestion.isDifficult == true { metadataBadge("难题", color: AppTheme.danger) }
                    if questionBankContext.currentQuestion.needsReview == true { metadataBadge("待复习", color: AppTheme.warning) }
                }
            }
            if let status = recordType {
                Text(clean(status))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor(status))
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(statusColor(status).opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
            }
            if isQuantityRelations {
                metadataTextLine("题型", value: QuantityQuestionTypeCatalog.displayName(for: activeModule))
                metadataTextLine("题目结构", value: firstText(["quantityStructure"]) ?? "")
                metadataTagLine("考点", values: knowledgePoints, emphasis: .strong)
                metadataTagLine("弱项标签", values: weaknessTags, emphasis: .subtle)
            } else {
                if let questionBankContext,
                   let questionType = QuestionBankQuestionHeading.displayLabel(
                       type: questionBankContext.currentQuestion.type,
                       subject: questionBankContext.currentQuestion.subject,
                       moduleTitle: questionBankContext.moduleTitle
                   ) {
                    metadataTextLine("题型", value: questionType)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("question-bank-detail-question-type")
                }
                metadataTagLine(knowledgePointLabel, values: knowledgePoints, emphasis: .strong)
                if isDataAnalysis || isAnalogyReasoning {
                    metadataTextLine(errorCauseLabel, value: firstText(["errorCause", "cause", "reason"]) ?? "")
                } else {
                    metadataTagLine(errorCauseLabel, values: splitTags(firstText(["errorCause", "cause", "reason"]) ?? ""), emphasis: .subtle)
                }
                metadataTextLine(isDataAnalysis ? "提醒" : "思维误区", value: firstText(["pitfall", "misconception", "thinkingTrap"]) ?? "")
                if isGraphReasoning {
                    metadataTextLine("图形规律", value: firstText(["graphRule", "patternRule"]) ?? "")
                    metadataTextLine("识别思路", value: firstText(["recognition", "recognitionPath"]) ?? "")
                }
            }
        }
    }

    @ViewBuilder private var questionBankMaterialBlock: some View {
        if let context = displayQuestionBankContext, let material = context.material {
            VStack(alignment: .leading, spacing: 9) {
                Text("共用材料")
                    .font(AppTheme.sectionTitleFont)
                if !material.text.isEmpty {
                    Text(verbatim: material.text)
                        .font(QuestionBankTypography.contentFont)
                        .lineSpacing(QuestionBankTypography.contentLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !material.imageAssetID.isEmpty,
                   let asset = context.assetsByID[material.imageAssetID] {
                    QuestionBankLocalImage(asset: asset, sizing: .material, activationTab: .questionBank)
                }
                ForEach(Array(context.materialSourceRows.enumerated()), id: \.offset) { _, row in
                    supportingLine("材料来源", value: row, systemImage: "books.vertical.fill")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(detailBackground, in: RoundedRectangle(cornerRadius: 10))
        }
    }

    @ViewBuilder private func imagesBlock(availableWidth: CGFloat) -> some View {
        if let context = displayQuestionBankContext {
            if !context.currentQuestion.stemImageAssetID.isEmpty,
               let asset = context.assetsByID[context.currentQuestion.stemImageAssetID] {
                QuestionBankLocalImage(
                    asset: asset,
                    sizing: .stem,
                    activationTab: questionBankContext == nil ? .library : .questionBank
                )
                    .padding(.top, 3)
            }
        } else if !imageValues.isEmpty {
            let widthFractions = LibraryImageDisplaySetting.widthFractions(
                from: object["imageDisplayMetadata"],
                count: imageValues.count
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(imageValues.enumerated()), id: \.offset) { index, source in
                    LibraryDetailImage(
                        source: source,
                        cacheKey: "detail-\(activeRecordID)-\(record?.updatedAt?.timeIntervalSince1970 ?? 0)-\(index)-\(source.count)",
                        availableWidth: availableWidth,
                        widthFraction: widthFractions[index]
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 3)
        }
    }

    @ViewBuilder private var questionBlock: some View {
        if let rawQuestion = firstText(["question", "title", "name", "text", "content"]),
           !clean(rawQuestion).isEmpty {
            Text(cleanMultiline(rawQuestion))
                .font(questionBankContext == nil ? AppTheme.questionTextFont : QuestionBankTypography.contentFont)
                .lineSpacing(questionBankContext == nil ? AppTheme.questionLineSpacing : QuestionBankTypography.contentLineSpacing)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(detailBackground, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier(
                    questionBankContext.map { "question-bank-detail-stem-\($0.question.id)" }
                        ?? "library-record-detail-stem"
                )
        }
    }

    @ViewBuilder private var optionsBlock: some View {
        let options = stringArray("options") ?? []
        let optionImages = optionImageValues
        let bankContext = self.displayQuestionBankContext
        let optionCount = max(options.count, optionImages.count)
        if optionCount > 0 {
            VStack(spacing: bankContext == nil ? 8 : 6) {
                ForEach(0..<optionCount, id: \.self) { index in
                    let option = index < options.count ? options[index] : ""
                    let optionImage = index < optionImages.count ? optionImages[index] : ""
                    let letter = String(UnicodeScalar(65 + index)!)
                    let correct = answerLetters.contains(letter)
                    let chosen = userAnswerLetters.contains(letter)
                    let hasText = !clean(option).isEmpty
                    HStack(
                        alignment: QuestionBankOptionRowLayout.verticalAlignment(hasText: hasText),
                        spacing: 8
                    ) {
                        QuestionBankOptionMarker(
                            letter: letter,
                            state: optionMarkerState(correct: correct, chosen: chosen),
                            diameter: 26,
                            font: bankContext == nil ? .system(size: 14) : QuestionBankTypography.contentFont
                        )
                        VStack(alignment: .leading, spacing: bankContext == nil ? 8 : 6) {
                            if hasText {
                                optionText(option)
                                    .lineSpacing(bankContext == nil ? 5.5 : QuestionBankTypography.contentLineSpacing)
                            }
                            if !optionImage.isEmpty {
                                if let bankContext,
                                   let asset = bankContext.assetsByID[optionImage] {
                                    QuestionBankLocalImage(asset: asset, sizing: .option, activationTab: .questionBank)
                                } else if questionBankContext == nil {
                                    LibraryDetailImage(
                                        source: optionImage,
                                        cacheKey: "detail-option-\(activeRecordID)-\(index)-\(optionImage.count)",
                                        availableWidth: nil,
                                        widthFraction: LibraryImageDisplaySetting.maximumWidthFraction
                                    )
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .alignmentGuide(.firstTextBaseline) { dimensions in
                            dimensions[.firstTextBaseline]
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(optionBackground(correct: correct, chosen: chosen), in: RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                optionBorderColor(correct: correct, chosen: chosen),
                                lineWidth: questionBankContext == nil && (chosen || correct) ? 1 : 0.8
                            )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var answerAndSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let questionBankContext {
                if questionBankShowsAnswer {
                    QuestionBankReferenceAccuracyControl(
                        record: questionBankContext.record,
                        accuracy: questionBankContext.currentQuestion.accuracy
                    )
                }
            } else if let accuracy = formattedAccuracy {
                supportingLine("参考正确率", value: accuracy, systemImage: "chart.bar.fill")
            }
            if !questionSourceRows.isEmpty {
                questionSourceDisclosure(rows: questionSourceRows)
            }
        }
        .padding(.top, 4)
    }

    private func questionSourceDisclosure(rows: [String]) -> some View {
        let isExpanded = expandedQuestionSourceID == questionSourceIdentity
        return VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    expandedQuestionSourceID = isExpanded ? nil : questionSourceIdentity
                }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: "books.vertical.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text("题目来源")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.secondary)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("题目来源")
            .accessibilityValue(isExpanded ? "已展开" : "已折叠")
            .accessibilityIdentifier("question-source-disclosure")

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        Text(row)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 23)
                .accessibilityIdentifier("question-source-rows")
            }
        }
        .padding(.vertical, 2)
    }

    private var questionSourceRows: [String] {
        if let context = displayQuestionBankContext, !context.sourceRows.isEmpty {
            return context.sourceRows
        }
        guard let source = firstText(["questionSource", "source"]) else { return [] }
        let fallbackNumber = sourceQuestionNumber(in: firstText(["questionNumber"]) ?? "")
        var seen = Set<String>()
        return source.components(separatedBy: .newlines).compactMap { rawRow in
            let cleanedRow = clean(rawRow)
            guard !cleanedRow.isEmpty else { return nil }
            let number = sourceQuestionNumber(in: cleanedRow) ?? fallbackNumber
            let fileNameInput = cleanedRow.replacingOccurrences(
                of: #"[·／/\-\s]*(?:原)?第?\s*\d+\s*题"#,
                with: "",
                options: .regularExpression
            )
            let fileName = QuestionBankSourceDisplay.cleanedFileName(fileNameInput)
            guard !fileName.isEmpty else { return nil }
            let row = number.map { "\(fileName)·第\($0)题" } ?? fileName
            return seen.insert(row).inserted ? row : nil
        }
    }

    private var questionSourceIdentity: String {
        if let question = displayQuestionBankContext?.currentQuestion {
            return "\(question.paperID)|\(question.id)"
        }
        return record?.compoundID ?? "library-record"
    }

    private func sourceQuestionNumber(in value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed.allSatisfy({ $0.isNumber }) { return trimmed }
        guard let range = trimmed.range(
            of: #"(?:原)?第?\s*\d+\s*题"#,
            options: .regularExpression
        ) else { return nil }
        let digits = String(trimmed[range].filter { $0.isNumber })
        return digits.isEmpty ? nil : digits
    }

    @ViewBuilder private var explanationBlock: some View {
        if questionBankContext?.isAnswerRevealed == true,
           let explanation = firstText(["explanation"]),
           !clean(explanation).isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("解析", systemImage: "text.book.closed")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cleanMultiline(explanation))
                    .font(.system(size: 14))
                    .lineSpacing(5)
                    .textSelection(.enabled)
            }
            .padding(.top, 5)
        }
    }

    @ViewBuilder private var comparisonBlock: some View {
        let words = linkedWordRecords
        if isLogicFillError || !words.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("关联词语库")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    if isLogicFillError {
                        Button("选择关联") { showWordSelection = true }
                            .font(.system(size: 12, weight: .medium))
                            .buttonStyle(.plain)
                            .foregroundStyle(AppTheme.accent)
                    }
                }
                if words.isEmpty {
                    Text("尚未关联词语，可在这里直接选择词语库内容")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.tertiary)
                }
                ForEach(words, id: \.compoundID) { word in
                    Button {
                        if let onOpenLinkedWord { onOpenLinkedWord(word.recordID) }
                        else { linkedWordDetailTarget = LinkedWordDetailTarget(recordID: word.recordID) }
                    } label: {
                        let wordSnapshot = LibraryRecordSnapshot(record: word)
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(wordSnapshot.title).font(.system(size: 13, weight: .medium)).foregroundStyle(.primary)
                                if !wordSnapshot.summary.isEmpty {
                                    Text(wordSnapshot.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 4)
        }
    }

    private var noteBlock: some View {
        Group {
            if let questionBankContext {
                LibraryInlineNoteView(
                    session: noteSession,
                    title: "题目笔记",
                    readNote: { object["note"] as? String ?? "" },
                    writeNote: { note, _ in
                        var fields = questionBankAnalysisFields
                        fields.note = note
                        try persistQuestionBankAnalysis(fields)
                    },
                    renderDocumentID: questionBankContext.question.id,
                    renderVersion: { String(questionBankContext.record.contentRevision) }
                )
            } else if let record {
                LibraryInlineNoteView(record: record, session: noteSession)
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var linkedErrorBlock: some View {
        if questionBankContext != nil, !linkedErrorRecords.isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Label("关联错题", systemImage: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                ForEach(linkedErrorRecords, id: \.compoundID) { error in
                    let snapshot = LibraryRecordSnapshot(record: error)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(snapshot.title).font(.system(size: 13, weight: .medium))
                        if !snapshot.summary.isEmpty {
                            Text(snapshot.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder private var reviewBlock: some View {
        if let value = firstText(["reviewNote", "reviewPlan", "nextReviewAt"]), !clean(value).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Label("复盘记录", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(cleanMultiline(value)).font(.system(size: 14, weight: .regular)).lineSpacing(6)
            }
            .padding(.top, 4)
        }
    }

    private enum MetadataTagEmphasis: Equatable { case strong, subtle }

    @ViewBuilder
    private func metadataTagLine(_ label: String, values: [String], emphasis: MetadataTagEmphasis) -> some View {
        let cleanedValues = values.map(clean).filter { !$0.isEmpty }
        if !cleanedValues.isEmpty {
            HStack(alignment: .top, spacing: 6) {
                Text("\(label)：")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.primary)
                    .padding(.top, 3)
                    .fixedSize(horizontal: true, vertical: false)
                NativeTagFlow(spacing: 5) {
                    ForEach(cleanedValues, id: \.self) { value in
                        Text(value)
                            .font(.system(size: 12.5, weight: emphasis == .strong ? .medium : .regular))
                            .foregroundStyle(emphasis == .strong ? AppTheme.accent : Color.secondary)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                emphasis == .strong ? AppTheme.accent.opacity(0.10) : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func metadataTextLine(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(label)：")
            Text(clean(value)).frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(size: 12.5, weight: .regular))
        .foregroundStyle(.primary)
    }

    private func supportingLine(_ label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text("\(label)：")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 12, weight: .regular))
    }

    private func optionText(_ option: String) -> Text {
        Text(cleanMultiline(option))
            .font(questionBankContext == nil ? .system(size: 14, weight: .regular) : QuestionBankTypography.contentFont)
    }

    private var answerLetters: Set<String> { letterSet(firstText(["correctOption", "answer", "correctAnswer"])) }
    private var userAnswerLetters: Set<String> { letterSet(firstText(["userOption", "myAnswer"])) }
    private func letterSet(_ value: String?) -> Set<String> {
        Set((value ?? "").uppercased().filter { "ABCD".contains($0) }.map(String.init))
    }
    private func optionBackground(correct: Bool, chosen: Bool) -> Color {
        if questionBankContext != nil { return Color.white }
        if correct { return Color(red: 232.0 / 255.0, green: 245.0 / 255.0, blue: 233.0 / 255.0) }
        if chosen { return Color(red: 255.0 / 255.0, green: 235.0 / 255.0, blue: 238.0 / 255.0) }
        return Color.white
    }

    private func optionMarkerState(correct: Bool, chosen: Bool) -> QuestionBankOptionMarkerState {
        if questionBankContext != nil {
            guard questionBankShowsAnswer else { return chosen ? .selected : .unselected }
            if correct { return .correct }
            if chosen { return .incorrect }
            return .unselected
        }
        if correct { return .correct }
        if chosen { return .incorrect }
        return .unselected
    }

    private func optionBorderColor(correct: Bool, chosen: Bool) -> Color {
        guard questionBankContext == nil else { return webBorder }
        return correct ? webSuccess : (chosen ? AppTheme.danger : webBorder)
    }

    private var questionBankShowsAnswer: Bool {
        guard let questionBankContext else { return false }
        return questionBankContext.isAnswerRevealed
            && !questionBankContext.currentQuestion.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func metadataBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var webSuccess: Color { Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0) }
    private var webBorder: Color { Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 242.0 / 255.0) }

    private var detailBackground: Color { Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0) }

    private var recordType: String? {
        if let value = firstText(["type"]),
           QuestionBankErrorBookCategory.allCases.contains(where: { $0.rawValue == clean(value) }) {
            return clean(value)
        }
        return firstText(["status", "masteryStatus"]).map(clean)
    }

    private var knowledgePoints: [String] {
        if let values = stringArray("knowledgePoints"), !values.isEmpty { return values }
        return textValues(["knowledgePoint", "point", "topic"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var displayQuestionBankContext: QuestionBankQuestionAnalysisContext? {
        questionBankContext ?? linkedQuestionBankContext
    }

    private var linkedQuestionContextKey: String {
        guard questionBankContext == nil,
              kind == .errors,
              let payload = record?.jsonObject,
              let paperID = payload["questionBankPaperID"] as? String,
              let questionID = payload["questionBankQuestionID"] as? String else { return "" }
        return "\(paperID)|\(questionID)|\(payload["userOption"] as? String ?? "")|\(record?.updatedAt?.timeIntervalSince1970 ?? 0)"
    }

    @MainActor
    private func loadLinkedQuestionContext() {
        guard questionBankContext == nil,
              kind == .errors,
              let payload = record?.jsonObject,
              let paperID = payload["questionBankPaperID"] as? String,
              let questionID = payload["questionBankQuestionID"] as? String else {
            linkedQuestionBankContext = nil
            return
        }
        linkedQuestionBankContext = QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: paperID,
            questionID: questionID,
            selectedOption: payload["userOption"] as? String ?? "",
            context: modelContext
        )
    }

    private var imageValues: [String] {
        if let values = object["images"] as? [String], !values.isEmpty { return values }
        return firstText(["image"]).map { [$0] } ?? []
    }

    private var linkedWordRecords: [StoredRecord] {
        let ids = Set(object["linkedWordIds"] as? [String] ?? [])
        return records.filter { $0.collection == "words" && ids.contains($0.recordID) }
    }

    private var linkedErrorRecords: [StoredRecord] {
        let ids = Set(object["linkedErrorRecordIDs"] as? [String] ?? [])
        return records.filter { $0.collection == "errors" && ids.contains($0.recordID) }
    }

    private var optionImageValues: [String] {
        (object["optionImages"] as? [String]) ?? []
    }

    private var weaknessTags: [String] {
        if let values = stringArray("weaknessTags"), !values.isEmpty { return values }
        return textValues(["weaknessTags"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var isLogicFillError: Bool {
        activeSubject == "言语理解" && activeModule == "逻辑填空"
    }

    private var isLogicJudgment: Bool {
        activeSubject == "判断推理" && activeModule == "逻辑判断"
    }

    private var isAnalogyReasoning: Bool {
        activeSubject == "判断推理" && activeModule == "类比推理"
    }

    private var isDataAnalysis: Bool {
        activeSubject == "资料分析"
    }

    private var isQuantityRelations: Bool {
        activeSubject == "数量关系"
    }

    private var isGraphReasoning: Bool {
        activeSubject == "判断推理" && activeModule == "图形推理"
    }

    private var knowledgePointLabel: String { isLogicJudgment ? "题干逻辑结构" : "考点" }
    private var errorCauseLabel: String {
        if isLogicJudgment { return "选项逻辑作用" }
        if isAnalogyReasoning { return "二级辨析" }
        return "错因"
    }

    private func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var dateBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let createdAt = record?.createdAt {
                Text("收录于 \(Self.dateFormatter.string(from: createdAt))")
            }
            if let updatedAt = record?.updatedAt {
                Text("上次更新 \(Self.dateFormatter.string(from: updatedAt))")
            }
        }
        .font(.system(size: 11, weight: .regular))
        .foregroundStyle(.tertiary)
        .padding(.top, 8)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private var linkedWordSelection: Binding<[String]> {
        Binding(
            get: { object["linkedWordIds"] as? [String] ?? [] },
            set: { newIDs in
                if let record {
                    try? LibraryRecordRepository.updateLinkedWords(
                        error: record,
                        newIDs: newIDs,
                        wordRecords: records,
                        context: modelContext
                    )
                } else if questionBankContext != nil {
                    var fields = questionBankAnalysisFields
                    fields.linkedWordIDs = newIDs
                    try? persistQuestionBankAnalysis(fields)
                }
            }
        )
    }

    private func linkNewWord(_ id: String) {
        var ids = object["linkedWordIds"] as? [String] ?? []
        if !ids.contains(id) { ids.append(id) }
        if let record {
            try? LibraryRecordRepository.updateLinkedWords(
                error: record,
                newIDs: ids,
                wordRecords: records,
                context: modelContext
            )
        } else if questionBankContext != nil {
            var fields = questionBankAnalysisFields
            fields.linkedWordIDs = ids
            try? persistQuestionBankAnalysis(fields)
        }
    }

    private var formattedAccuracy: String? {
        guard let raw = firstText(["accuracy", "correctRate"]), !clean(raw).isEmpty else { return nil }
        let value = clean(raw)
        return value.contains("%") ? value : "\(value)%"
    }

    private func statusColor(_ value: String) -> Color {
        value.contains("不确定") ? AppTheme.warning : AppTheme.danger
    }

    private func textValues(_ keys: [String]) -> [String] {
        firstText(keys).map { [$0] } ?? []
    }

    private func openDoodle() {
        let openStart = ProcessInfo.processInfo.systemUptime
        let drawingData = firstText(["pencilKitData", "drawingData"]) ?? ""
        let targetID = activeRecordID
        let doodleLoadState = questionBankContext == nil
            ? .unknown
            : QuestionBankDoodleMemoryCache.shared.state(for: targetID)
        let needsBackgroundLoad = questionBankContext != nil && doodleLoadState == .unknown
        let currentDrawing = questionBankContext == nil
            ? drawingData
            : (doodleLoadState.drawingData ?? "")
        doodleSession.present(
            targetRecordID: targetID,
            drawingData: currentDrawing,
            legacyPreviewDataURL: questionBankContext == nil && currentDrawing.isEmpty
                ? (firstText(["drawingPreview", "doodle", "drawingDataURL"]) ?? "") : "",
            isLoadingDrawing: needsBackgroundLoad,
            source: "library-record-detail",
            onSave: { updatedDrawing, legacyPreviewCleared, generation, revision in
                if questionBankContext != nil {
                    QuestionBankDoodleRepository.enqueueSave(
                        recordID: targetID,
                        drawingData: updatedDrawing,
                        container: modelContext.container,
                        presentationGeneration: generation,
                        drawingRevision: revision,
                        debounceMilliseconds: 0
                    ) { error in
                        guard doodleSession.presentationGeneration == generation,
                              doodleSession.targetRecordID == targetID else { return }
                        doodleSession.saveError = error
                    }
                    return nil
                }
                return saveDrawing(updatedDrawing, legacyPreviewCleared: legacyPreviewCleared)
            }
        )
        LibraryPerformanceLog.mark("doodle.tap-to-feedback", since: openStart)
        LibraryPerformanceLog.mark("doodle.tap-to-present", since: openStart)
        if needsBackgroundLoad {
            let container = modelContext.container
            doodleSession.beginDrawingLoad(recordID: targetID, startedAt: openStart) {
                try await QuestionBankDoodleRepository.drawingData(
                    recordID: targetID,
                    container: container
                )
            } onLoaded: { loadedDrawing in
                QuestionBankDoodleMemoryCache.shared.store(loadedDrawing, for: targetID)
            }
        }
        // The drawing overlay is already presented; finish the editor through
        // UITextView's end-editing callback before committing the final draft.
        noteSession.finish { _ in }
    }
    private func saveDrawing(_ drawingData: String, legacyPreviewCleared: Bool) -> String? {
        guard let record else { return nil }
        return LibraryDoodlePersistence.save(
            record: record,
            context: modelContext,
            drawingData: drawingData,
            legacyPreviewCleared: legacyPreviewCleared
        )
    }

    private var activeRecordID: String {
        questionBankContext?.doodleRecordID ?? record?.compoundID ?? ""
    }

    private var activeSubject: String {
        questionBankContext?.typeMapping.subject ?? record?.subject ?? scope.subject ?? ""
    }

    private var activeModule: String {
        questionBankContext?.typeMapping.module ?? record?.module ?? scope.module ?? ""
    }

    private var questionBankAnalysisFields: QuestionBankQuestionAnalysisFields {
        var fields = QuestionBankQuestionAnalysisFields()
        fields.errorCause = object["errorCause"] as? String ?? ""
        fields.pitfall = object["pitfall"] as? String ?? ""
        fields.quantityStructure = object["quantityStructure"] as? String ?? ""
        fields.graphRule = object["graphRule"] as? String ?? ""
        fields.recognition = object["recognition"] as? String ?? ""
        fields.note = object["note"] as? String ?? ""
        fields.knowledgePoints = stringArray("knowledgePoints") ?? []
        fields.weaknessTags = stringArray("weaknessTags") ?? []
        fields.linkedWordIDs = object["linkedWordIds"] as? [String] ?? []
        fields.linkedErrorRecordIDs = object["linkedErrorRecordIDs"] as? [String] ?? []
        fields.questionSource = questionBankContext?.sourceRows.joined(separator: "\n") ?? ""
        fields.questionNumber = questionBankContext.map { String($0.question.number) } ?? ""
        return fields
    }

    private func persistQuestionBankAnalysis(_ fields: QuestionBankQuestionAnalysisFields) throws {
        guard let questionBankContext else { return }
        let question = questionBankContext.currentQuestion
        logQuestionBankDetailLifecycle("analysis-save-before")
        try QuestionBankRepository.updateQuestionAnalysis(
            record: questionBankContext.record,
            paperID: question.paperID,
            questionID: question.id,
            stem: question.stem,
            optionTexts: Dictionary(question.options.map { ($0.id, $0.text) }, uniquingKeysWith: { first, _ in first }),
            answerOptionID: question.answer,
            annotations: QuestionBankQuestionAnnotations(question: question),
            analysis: fields,
            typeMapping: questionBankContext.typeMapping,
            sourceRows: questionBankContext.sourceRows,
            context: modelContext
        )
        object["note"] = fields.note
        object["linkedWordIds"] = fields.linkedWordIDs
        object["linkedErrorRecordIDs"] = fields.linkedErrorRecordIDs
        logQuestionBankDetailLifecycle("analysis-save-after")
    }

    private func logQuestionBankDetailLifecycle(_ event: String) {
        #if DEBUG
        guard QuestionBankReaderUITestFixture.isEnabled else { return }
        let context = questionBankContext
        let routeID = context?.question.id ?? "library-record"
        let revision = context.map { String($0.record.contentRevision) } ?? "none"
        let payloadBytes = context.map { String($0.record.payload.count) } ?? "none"
        let stemCharacters = context.map { String($0.currentQuestion.stem.count) } ?? "none"
        let noteCharacters = String((context?.currentQuestion.note ?? "").count)
        let objectNoteCharacters = String((object["note"] as? String ?? "").count)
        NSLog("%@", "[QBankDetailLifecycle] event=\(event) route=\(routeID) context=\(context == nil ? "missing" : "present") revision=\(revision) payloadBytes=\(payloadBytes) stemChars=\(stemCharacters) questionNoteChars=\(noteCharacters) viewNoteChars=\(objectNoteCharacters)")
        #endif
    }

    private func firstText(_ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }
    private func stringArray(_ key: String) -> [String]? {
        if let values = object[key] as? [String] { return values }
        if let values = object[key] as? [[String: Any]] { return values.compactMap { ($0["text"] ?? $0["content"] ?? $0["value"]) as? String } }
        return nil
    }
    private func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "(?:^|\\s)[.#]?[a-zA-Z][^{}\\n]{0,80}\\{[^}]*\\}", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func cleanMultiline(_ value: String) -> String {
        value
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<style[\\s\\S]*?</style>", with: " ", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

private struct LibraryDetailImage: View {
    let source: String
    let cacheKey: String
    let availableWidth: CGFloat?
    let widthFraction: Double
    @State private var image: UIImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(uiColor: .secondarySystemBackground)
                    .frame(height: 120)
                    .overlay {
                        if didFail {
                            Label("图片无法加载", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
            }
        }
        .frame(width: availableWidth.map { max(1, $0 * CGFloat(widthFraction)) })
        .frame(maxWidth: availableWidth == nil ? .infinity : nil)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .task(id: cacheKey) {
            image = nil
            didFail = false
            let loadedImage = await LibraryImageLoader.image(
                from: source,
                cacheKey: cacheKey,
                maximumPixelSize: 2_400
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFail = loadedImage == nil
        }
    }
}
