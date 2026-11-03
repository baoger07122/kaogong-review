import Foundation
import ImageIO
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
    let onEdit: () -> Void
    let onDelete: () -> Void
    var orderedRecordIDs: [String] = []
    var onNavigateToRecord: ((String) -> Void)? = nil
    var onOpenLinkedWord: ((String) -> Void)? = nil

    @State private var object: [String: Any]
    @State private var imageSourceIdentities: [String: LibraryDetailImageSourceIdentity]
    @State private var payloadDecodeFailed = false
    @State private var lastLocallySavedNoteUpdate: Date?

    @State private var showDelete = false
    @StateObject private var noteSession = LibraryInlineNoteSession()
    @State private var expandedQuestionSourceID: String?
    @State private var showWordSelection = false
    @State private var linkedWordCreationCategory: WordCategory?
    @State private var linkedWordDetailTarget: LinkedWordDetailTarget?
    @State private var linkedQuestionBankContext: QuestionBankQuestionAnalysisContext?
    @State private var linkedQuestionFallbackObject: [String: Any] = [:]

    init(
        kind: LibraryContentKind,
        scope: LibraryScope,
        record: StoredRecord,
        onEdit: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        orderedRecordIDs: [String] = [],
        onNavigateToRecord: ((String) -> Void)? = nil,
        onOpenLinkedWord: ((String) -> Void)? = nil
    ) {
        self.kind = kind
        self.scope = scope
        self.record = record
        self.onEdit = onEdit
        self.onDelete = onDelete
        self.orderedRecordIDs = orderedRecordIDs
        self.onNavigateToRecord = onNavigateToRecord
        self.onOpenLinkedWord = onOpenLinkedWord
        if let decodedObject = record.jsonObject {
            _object = State(initialValue: decodedObject)
            _imageSourceIdentities = State(initialValue: Self.makeImageSourceIdentities(for: decodedObject))
            _payloadDecodeFailed = State(initialValue: false)
        } else {
            _object = State(initialValue: [:])
            _imageSourceIdentities = State(initialValue: [:])
            _payloadDecodeFailed = State(initialValue: true)
        }
    }

    var body: some View {
        detailBehavior
    }

    private var detailBehavior: some View {
        detailStateTracking
            .task(id: linkedQuestionContextKey) { loadLinkedQuestionContext() }
    }

    private var detailStateTracking: some View {
        detailNavigationDestination
            .onChange(of: record?.updatedAt) { _, newValue in
                guard let record else { return }
                if let newValue,
                   let lastSavedAt = lastLocallySavedNoteUpdate,
                   newValue == lastSavedAt {
                    lastLocallySavedNoteUpdate = nil
                    return
                }
                if let decodedObject = record.jsonObject {
                    refreshObject(decodedObject)
                    payloadDecodeFailed = false
                } else {
                    refreshObject([:])
                    payloadDecodeFailed = true
                }
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
    }

    private var detailNavigationTitle: String {
        guard let context = displayQuestionBankContext else { return "错题详情" }
        return "第\(context.currentQuestion.number)题详情"
    }

    private var detailContent: some View {
        GeometryReader { proxy in
            let availableWidth = proxy.size.width.isFinite ? max(0, proxy.size.width) : 0
            ZStack {
                if payloadDecodeFailed {
                    NativeStatusCard(
                        title: "错题详情暂时无法读取",
                        detail: "原始记录数据无法解析。笔记和编辑保存已阻止，以保留数据库中的原始内容。",
                        systemImage: "exclamationmark.triangle",
                        color: AppTheme.warning
                    )
                    .padding(16)
                    .accessibilityIdentifier("library-record-detail-payload-error")
                } else {
                    detailScrollView(availableWidth: availableWidth)
                }
                detailModal
            }
        }
    }

    private func detailScrollView(availableWidth: CGFloat) -> some View {
        let readingColumnWidth = min(availableWidth.isFinite ? max(0, availableWidth) : 0, 920)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                metadata
                if kind == .errors && isDataAnalysis {
                    dataAnalysisMaterialBlock
                    imagesBlock(availableWidth: max(0, readingColumnWidth - 32))
                    questionBlock
                } else {
                    questionBankMaterialBlock
                    questionBlock
                    imagesBlock(availableWidth: max(0, readingColumnWidth - 32))
                }
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
        .simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded(navigateFromHorizontalSwipe)
        )
        .accessibilityIdentifier(displayQuestionBankContext.map {
            "question-bank-detail-scroll-\($0.question.id)"
        } ?? "library-record-detail-scroll")
    }

    private func navigateFromHorizontalSwipe(_ value: DragGesture.Value) {
        guard kind == .errors,
              !doodleSession.isPresented,
              !noteSession.isEditing,
              let onNavigateToRecord,
              let record,
              let currentIndex = orderedRecordIDs.firstIndex(of: record.recordID),
              abs(value.translation.width) >= 80,
              abs(value.translation.height) <= max(36, abs(value.translation.width) * 0.35)
        else { return }

        let nextIndex = currentIndex + (value.translation.width < 0 ? 1 : -1)
        guard orderedRecordIDs.indices.contains(nextIndex) else { return }
        onNavigateToRecord(orderedRecordIDs[nextIndex])
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
                candidates: records.filter {
                    LibraryRelationCandidateScope.includes(
                        candidateCollection: $0.collection,
                        targetCollection: "words"
                    )
                },
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
        if doodleSession.isPresented {
            toolbarPlaceholder
            toolbarPlaceholder
        } else {
            Button(action: openDoodle) { Image(systemName: "pencil.and.scribble") }
                .accessibilityLabel("涂鸦")
            questionActionsMenu
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
            Button {
                noteSession.finish { saved in
                    if saved { onEdit() }
                }
            } label: {
                Label("编辑错题", systemImage: "pencil")
            }
            Button(role: .destructive) {
                noteSession.finish { saved in
                    if saved { showDelete = true }
                }
            } label: {
                Label("删除错题", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("题目操作")
        .accessibilityIdentifier("library-record-actions")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 7) {
            let isDifficult = (object["isDifficult"] as? Bool) ?? (object["isDifficult"] as? NSNumber)?.boolValue ?? false
            let needsReview = (object["needsReview"] as? Bool) ?? (object["needsReview"] as? NSNumber)?.boolValue ?? false
            if isDifficult || needsReview || displayQuestionBankContext != nil {
                HStack(spacing: 6) {
                    if isDifficult || displayQuestionBankContext?.currentQuestion.isDifficult == true {
                        metadataBadge("难题", color: AppTheme.danger)
                    }
                    if needsReview || displayQuestionBankContext?.currentQuestion.needsReview == true {
                        metadataBadge("待复习", color: AppTheme.warning)
                    }
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
                if displayQuestionBankContext != nil, !activeModule.isEmpty {
                    metadataTextLine("题型", value: activeModule)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("question-bank-detail-question-type")
                }
                metadataTagLine(knowledgePointLabel, values: knowledgePoints, emphasis: .strong)
                if isDataAnalysis || isAnalogyReasoning {
                    metadataTextLine(errorCauseLabel, value: firstText(["errorCause", "cause", "reason"]) ?? "")
                } else {
                    metadataTagLine(errorCauseLabel, values: splitTags(firstText(["errorCause", "cause", "reason"]) ?? ""), emphasis: .subtle)
                }
                if isGraphReasoning {
                    metadataTextLine("图形规律", value: firstText(["graphRule", "patternRule"]) ?? "")
                    metadataTextLine("识别思路", value: firstText(["recognition", "recognitionPath"]) ?? "")
                }
            }
            let pitfall = firstText(["pitfall", "misconception", "thinkingTrap"]) ?? ""
            let reminder = firstText(["reminder"]) ?? ""
            if !isAnalogyReasoning || !pitfall.isEmpty {
                metadataTextLine("误区", value: pitfall)
            }
            if !isAnalogyReasoning || !reminder.isEmpty {
                metadataTextLine(isAnalogyReasoning ? "常识" : "提醒", value: reminder)
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
                        .font(AppTheme.questionTextFont)
                        .lineSpacing(AppTheme.questionLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !material.imageAssetID.isEmpty,
                   let asset = context.assetsByID[material.imageAssetID] {
                    LegacyQuestionBankAssetImage(asset: asset, sizing: .material)
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

    @ViewBuilder private var dataAnalysisMaterialBlock: some View {
        let material = firstText(["dataAnalysisMaterialText"]) ?? ""
        if !material.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("材料")
                    .font(AppTheme.sectionTitleFont)
                    .foregroundStyle(.primary)
                Text(verbatim: cleanMultiline(material))
                    .font(AppTheme.questionTextFont)
                    .lineSpacing(AppTheme.questionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
            }
        }
    }

    @ViewBuilder private func imagesBlock(availableWidth: CGFloat) -> some View {
        if !imageValues.isEmpty {
            let widthFractions = LibraryImageDisplaySetting.widthFractions(
                from: object["imageDisplayMetadata"],
                count: imageValues.count
            )
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(imageValues.enumerated()), id: \.offset) { index, source in
                    let metadata = (object["imageDisplayMetadata"] as? [[String: Any]] ?? [])
                    let imageMetadataID = index < metadata.count ? (metadata[index]["id"] as? String ?? "") : ""
                    if let asset = displayQuestionBankContext?.assetsByID[source] {
                        LegacyQuestionBankAssetImage(asset: asset, sizing: .stem)
                            .frame(maxWidth: max(1, availableWidth * CGFloat(widthFractions[index])), alignment: .leading)
                    } else {
                        LibraryDetailImage(
                            source: source,
                            cacheKey: imageCacheKey(kind: "image", index: index, source: source, metadataID: imageMetadataID),
                            availableWidth: availableWidth,
                            widthFraction: widthFractions[index],
                            showsFrame: false
                        )
                    }
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
                .font(.system(size: 14.5, weight: .regular))
                .lineSpacing(AppTheme.questionLineSpacing)
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(webBorder, lineWidth: 0.8)
                }
                .accessibilityIdentifier(
                    displayQuestionBankContext.map { "question-bank-detail-stem-\($0.question.id)" }
                        ?? "library-record-detail-stem"
                )
        }
    }

    @ViewBuilder private var optionsBlock: some View {
        let options = stringArray("options") ?? []
        let optionImages = optionImageValues
        let optionCount = max(options.count, optionImages.count)
        if optionCount > 0 {
            VStack(spacing: 8) {
                ForEach(0..<optionCount, id: \.self) { index in
                    let option = index < options.count ? options[index] : ""
                    let optionImage = index < optionImages.count ? optionImages[index] : ""
                    let letter = String(UnicodeScalar(65 + index)!)
                    let correct = answerLetters.contains(letter)
                    let chosen = userAnswerLetters.contains(letter)
                    let hasText = !clean(option).isEmpty
                    HStack(
                        alignment: StudyOptionRowLayout.verticalAlignment(hasText: hasText),
                        spacing: 8
                    ) {
                        StudyOptionMarker(
                            letter: letter,
                            state: optionMarkerState(correct: correct, chosen: chosen),
                            diameter: 26,
                            font: .system(size: 14)
                        )
                        VStack(alignment: .leading, spacing: 8) {
                            if hasText {
                                optionText(option)
                                    .lineSpacing(5.5)
                            }
                            if !optionImage.isEmpty {
                                if let asset = displayQuestionBankContext?.assetsByID[optionImage] {
                                    LegacyQuestionBankAssetImage(asset: asset, sizing: .option)
                                } else {
                                    let optionImageIDs = object["optionImageIDs"] as? [String] ?? []
                                    let optionImageID = optionImageIDs.indices.contains(index) ? optionImageIDs[index] : ""
                                    LibraryDetailImage(
                                        source: optionImage,
                                        cacheKey: imageCacheKey(kind: "option", index: index, source: optionImage, metadataID: optionImageID),
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
                                lineWidth: (chosen || correct) ? 1 : 0.8
                            )
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var answerAndSource: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let accuracy = formattedAccuracy {
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
        if displayQuestionBankContext?.isAnswerRevealed == true,
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
            if let record {
                LibraryInlineNoteView(
                    record: record,
                    session: noteSession,
                    readNote: {
                        if let note = object["note"] as? String { return note }
                        return ["content", "errorNote", "analysis"]
                            .compactMap { object[$0] as? String }
                            .first ?? ""
                    },
                    onSaved: { note in
                        object["note"] = note
                        lastLocallySavedNoteUpdate = record.updatedAt
                    }
                )
            }
        }
        .padding(.top, 6)
    }

    @ViewBuilder private var linkedErrorBlock: some View {
        if displayQuestionBankContext != nil, !linkedErrorRecords.isEmpty {
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
            .font(.system(size: 15, weight: .regular))
    }

    private var answerLetters: Set<String> { letterSet(firstText(["correctOption", "answer", "correctAnswer"])) }
    private var userAnswerLetters: Set<String> { letterSet(firstText(["userOption", "myAnswer"])) }
    private func letterSet(_ value: String?) -> Set<String> {
        Set((value ?? "").uppercased().filter { "ABCD".contains($0) }.map(String.init))
    }
    private func optionBackground(correct: Bool, chosen: Bool) -> Color {
        guard displayQuestionBankContext == nil || questionBankShowsAnswer else { return .white }
        if correct { return StudyOptionFeedbackPalette.correctBackground }
        if chosen { return StudyOptionFeedbackPalette.incorrectBackground }
        return .white
    }

    private func optionMarkerState(correct: Bool, chosen: Bool) -> StudyOptionMarkerState {
        guard questionBankShowsAnswer || displayQuestionBankContext == nil else {
            return chosen ? .selected : .unselected
        }
        if correct { return .correct }
        if chosen { return .incorrect }
        return .unselected
    }

    private func optionBorderColor(correct: Bool, chosen: Bool) -> Color {
        guard displayQuestionBankContext == nil || questionBankShowsAnswer else { return webBorder }
        return correct ? StudyOptionFeedbackPalette.correct : (chosen ? StudyOptionFeedbackPalette.incorrect : webBorder)
    }

    private var questionBankShowsAnswer: Bool {
        guard let displayQuestionBankContext else { return false }
        return displayQuestionBankContext.isAnswerRevealed
            && !displayQuestionBankContext.currentQuestion.answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func metadataBadge(_ title: String, color: Color) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }

    private var webBorder: Color { Color(red: 240.0 / 255.0, green: 240.0 / 255.0, blue: 242.0 / 255.0) }

    private var detailBackground: Color { Color(red: 245.0 / 255.0, green: 245.0 / 255.0, blue: 247.0 / 255.0) }

    private var recordType: String? {
        firstText(["type", "status", "masteryStatus"]).map(clean)
    }

    private var knowledgePoints: [String] {
        if let values = stringArray("knowledgePoints"), !values.isEmpty { return values }
        return textValues(["knowledgePoint", "point", "topic"])
            .flatMap { $0.split(whereSeparator: { "、,，".contains($0) }).map(String.init) }
    }

    private var displayQuestionBankContext: QuestionBankQuestionAnalysisContext? {
        linkedQuestionBankContext
    }

    private var linkedQuestionContextKey: String {
        guard kind == .errors,
              let paperID = object["questionBankPaperID"] as? String,
              let questionID = object["questionBankQuestionID"] as? String else { return "" }
        let question = (object["question"] as? String ?? object["title"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let options = object["options"] as? [String] ?? []
        let imageReferences = (object["images"] as? [String] ?? [])
            + (object["optionImages"] as? [String] ?? [])
        let hasLinkedImageReference = imageReferences.contains { value in
            !value.isEmpty && value.count < 256 && !value.contains("://") && !value.hasPrefix("/")
        }
        let materialID = (object["materialID"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard question.isEmpty || options.isEmpty || hasLinkedImageReference || !materialID.isEmpty else {
            return ""
        }
        return "\(paperID)|\(questionID)"
    }

    @MainActor
    private func loadLinkedQuestionContext() {
        guard !linkedQuestionContextKey.isEmpty,
              kind == .errors,
              let paperID = object["questionBankPaperID"] as? String,
              let questionID = object["questionBankQuestionID"] as? String else {
            linkedQuestionBankContext = nil
            linkedQuestionFallbackObject = [:]
            return
        }
        let context = QuestionBankQuestionAnalysisContext.linkedErrorContext(
            paperID: paperID,
            questionID: questionID,
            selectedOption: object["userOption"] as? String ?? "",
            context: modelContext
        )
        linkedQuestionBankContext = context
        linkedQuestionFallbackObject = context?.detailObject ?? [:]
    }

    private var imageValues: [String] {
        if let values = object["images"] as? [String], !values.isEmpty { return values }
        if let values = linkedQuestionFallbackObject["images"] as? [String], !values.isEmpty { return values }
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
        if let values = object["optionImages"] as? [String], !values.isEmpty { return values }
        return linkedQuestionFallbackObject["optionImages"] as? [String] ?? []
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
        }
    }

    private var formattedAccuracy: String? {
        let legacyAccuracy = displayQuestionBankContext?.currentQuestion.accuracy.map {
            String(format: "%.0f", $0 > 1 ? $0 : $0 * 100)
        }
        let raw = firstText(["accuracy", "correctRate"]) ?? legacyAccuracy
        guard let raw, !clean(raw).isEmpty else { return nil }
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
        doodleSession.present(
            targetRecordID: targetID,
            drawingData: drawingData,
            legacyPreviewDataURL: drawingData.isEmpty
                ? (firstText(["drawingPreview", "doodle", "drawingDataURL"]) ?? "") : "",
            source: "library-record-detail",
            onSave: { updatedDrawing, legacyPreviewCleared, _, _ in
                return saveDrawing(updatedDrawing, legacyPreviewCleared: legacyPreviewCleared)
            }
        )
        LibraryPerformanceLog.mark("doodle.tap-to-feedback", since: openStart)
        LibraryPerformanceLog.mark("doodle.tap-to-present", since: openStart)
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
        record?.compoundID ?? ""
    }

    private func imageCacheKey(kind: String, index: Int, source: String, metadataID: String) -> String {
        let slot = "\(kind):\(index)"
        let identity = imageSourceIdentities[slot]
        let version = identity?.source == source ? identity?.cacheToken : nil
        return "detail-\(activeRecordID)-\(slot)-\(metadataID.isEmpty ? "legacy" : metadataID)-\(version ?? "untracked")"
    }

    private func refreshObject(_ value: [String: Any]) {
        imageSourceIdentities = Self.reconciledImageSourceIdentities(for: value, previous: imageSourceIdentities)
        object = value
    }

    private static func makeImageSourceIdentities(for object: [String: Any]) -> [String: LibraryDetailImageSourceIdentity] {
        reconciledImageSourceIdentities(for: object, previous: [:])
    }

    private static func reconciledImageSourceIdentities(
        for object: [String: Any],
        previous: [String: LibraryDetailImageSourceIdentity]
    ) -> [String: LibraryDetailImageSourceIdentity] {
        var result: [String: LibraryDetailImageSourceIdentity] = [:]
        let imageValues = (object["images"] as? [String]).flatMap { $0.isEmpty ? nil : $0 }
            ?? (object["image"] as? String).map { [$0] }
            ?? []
        let optionValues = object["optionImages"] as? [String] ?? []
        for (kind, values) in [("image", imageValues), ("option", optionValues)] {
            for (index, source) in values.enumerated() where !source.isEmpty {
                let slot = "\(kind):\(index)"
                if let existing = previous[slot], existing.source == source {
                    result[slot] = existing
                } else {
                    result[slot] = LibraryDetailImageSourceIdentity(source: source, cacheToken: UUID().uuidString)
                }
            }
        }
        return result
    }

    private var activeSubject: String {
        let localSubject = record?.subject?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return localSubject.isEmpty
            ? (displayQuestionBankContext?.typeMapping.subject ?? scope.subject ?? "")
            : localSubject
    }

    private var activeModule: String {
        let localModule = record?.module?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return localModule.isEmpty
            ? (displayQuestionBankContext?.typeMapping.module ?? scope.module ?? "")
            : localModule
    }

    private func firstText(_ keys: [String]) -> String? {
        for key in keys {
            if let value = object[key] as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = object[key] as? NSNumber { return value.stringValue }
            if let value = linkedQuestionFallbackObject[key] as? String,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return value }
            if let value = linkedQuestionFallbackObject[key] as? NSNumber { return value.stringValue }
        }
        return nil
    }
    private func stringArray(_ key: String) -> [String]? {
        if let values = object[key] as? [String], !values.isEmpty { return values }
        if let values = object[key] as? [[String: Any]] { return values.compactMap { ($0["text"] ?? $0["content"] ?? $0["value"]) as? String } }
        if let values = linkedQuestionFallbackObject[key] as? [String], !values.isEmpty { return values }
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

private struct LibraryDetailImageSourceIdentity {
    let source: String
    let cacheToken: String
}

private struct LibraryDetailImage: View {
    let source: String
    let cacheKey: String
    let availableWidth: CGFloat?
    let widthFraction: Double
    var showsFrame = true
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var appearanceRevision: UInt64 = 0

    var body: some View {
        Group {
            if showsFrame {
                imageContent
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                    }
            } else {
                imageContent
            }
        }
        .task(id: "\(cacheKey)|\(appearanceRevision)") {
            didFail = false
            if let cached = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 2_400) {
                image = cached
                LibraryPerformanceLog.event("image.cache-hit id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
                return
            }
            LibraryPerformanceLog.event("image.request id=\(LibraryPerformanceLog.shortIdentifier(cacheKey)) pixel=2400")
            let loadedImage = await LibraryImageLoader.image(
                from: source,
                cacheKey: cacheKey,
                maximumPixelSize: 2_400,
                requestID: UUID()
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFail = loadedImage == nil
            if loadedImage == nil {
                LibraryPerformanceLog.event("image.decode-failed id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
            }
        }
        .onChange(of: cacheKey) { _, newValue in
            image = LibraryImageLoader.cachedImage(cacheKey: newValue, maximumPixelSize: 2_400)
            didFail = false
        }
        .onAppear {
            appearanceRevision &+= 1
            image = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 2_400)
            didFail = false
        }
        .onDisappear { image = nil }
    }

    private var imageContent: some View {
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
    }
}

private final class LegacyQuestionBankImageBox: @unchecked Sendable {
    let image: UIImage

    init(image: UIImage) {
        self.image = image
    }
}

private enum LegacyQuestionBankImageCache {
    static let images: NSCache<NSString, LegacyQuestionBankImageBox> = {
        let cache = NSCache<NSString, LegacyQuestionBankImageBox>()
        cache.countLimit = 48
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()

    static func cachedImage(for key: String) -> UIImage? {
        images.object(forKey: key as NSString)?.image
    }

    static func decode(url: URL, cacheKey: String, maximumPixelSize: Int) -> LegacyQuestionBankImageBox? {
        guard !Task.isCancelled,
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              !Task.isCancelled else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        let box = LegacyQuestionBankImageBox(image: UIImage(cgImage: image))
        let cost = max(1, image.bytesPerRow * image.height)
        images.setObject(box, forKey: cacheKey as NSString, cost: cost)
        return box
    }
}

private struct LegacyQuestionBankAssetImage: View {
    enum Sizing: String {
        case material
        case stem
        case option
    }

    let asset: QuestionBankAssetReference
    let sizing: Sizing
    @State private var image: UIImage?
    @State private var failedToLoad = false

    private var cacheKey: String {
        [asset.compoundID, asset.assetRelativePath ?? "", String(asset.contentRevision), sizing.rawValue]
            .joined(separator: "|")
    }

    var body: some View {
        Group {
            if let image {
                imageView(image)
            } else if failedToLoad {
                Label("图片无法读取", systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color(uiColor: .secondarySystemBackground))
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 72)
            }
        }
        .task(id: cacheKey) {
            image = nil
            failedToLoad = false
            if let cached = LegacyQuestionBankImageCache.cachedImage(for: cacheKey) {
                image = cached
                return
            }
            guard let url = LegacyQuestionBankAssetStore.url(for: asset.assetRelativePath) else {
                failedToLoad = true
                return
            }
            let key = cacheKey
            let maximumPixelSize = sizing == .option ? 900 : 2_400
            let decodeTask = Task.detached(priority: .userInitiated) {
                LegacyQuestionBankImageCache.decode(
                    url: url,
                    cacheKey: key,
                    maximumPixelSize: maximumPixelSize
                )
            }
            let result = await withTaskCancellationHandler {
                await decodeTask.value
            } onCancel: {
                decodeTask.cancel()
            }
            guard !Task.isCancelled, cacheKey == key else { return }
            image = result?.image
            failedToLoad = result == nil
        }
        .onAppear {
            image = LegacyQuestionBankImageCache.cachedImage(for: cacheKey)
            failedToLoad = false
        }
    }

    @ViewBuilder
    private func imageView(_ image: UIImage) -> some View {
        switch sizing {
        case .material, .stem:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, alignment: .leading)
        case .option:
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 220, maxHeight: 126, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
