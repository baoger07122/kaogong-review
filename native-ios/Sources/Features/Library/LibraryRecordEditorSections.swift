import PhotosUI
import SwiftUI
import UIKit

/// Concrete form boundaries keep the new-record view's type tree shallow. Draft and
/// modal state stay owned by LibraryRecordEditorView and flow into these sections.
struct LibraryErrorEditorFieldsView: View {
    let recordID: String?
    let records: [StoredRecord]
    let splitMessage: String?
    let internalLinks: [RichTextInternalLink]
    let onOpenSmartSplit: () -> Void
    let onQuestionImageWidth: (String) -> Double
    let questionImageWidthBinding: (String) -> Binding<Double>
    let onCommitQuestionImageWidth: (String) -> Void
    let onOpenInternalLink: (RichTextInternalLink) -> Void
    let onOpenLinkedWord: (String) -> Void
    @Binding var draft: LibraryRecordDraft
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var activeTags: ManagedTagKind?
    @Binding var activeRelation: String?
    @Binding var expandedAnswerField: ErrorAnswerField?
    @Binding var showQuantityKnowledgePoints: Bool
    @Binding var showQuantityWeaknessTags: Bool
    @Binding var isCurrentAffairsSupplementExpanded: Bool
    @Binding var questionImageWidthPreview: [String: Double]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if draft.subject == "申论" {
                LibraryShenlunEditorForm(
                    draft: $draft,
                    activeRelation: $activeRelation,
                    isCurrentAffairsSupplementExpanded: $isCurrentAffairsSupplementExpanded,
                    internalLinks: internalLinks,
                    onOpenInternalLink: onOpenInternalLink,
                    records: records
                )
            } else {
                LibraryStandardErrorEditorForm(
                    recordID: recordID,
                    records: records,
                    splitMessage: splitMessage,
                    onOpenSmartSplit: onOpenSmartSplit,
                    onQuestionImageWidth: onQuestionImageWidth,
                    questionImageWidthBinding: questionImageWidthBinding,
                    onCommitQuestionImageWidth: onCommitQuestionImageWidth,
                    draft: $draft,
                    selectedPhotos: $selectedPhotos,
                    activeTags: $activeTags,
                    activeRelation: $activeRelation,
                    expandedAnswerField: $expandedAnswerField,
                    showQuantityKnowledgePoints: $showQuantityKnowledgePoints,
                    showQuantityWeaknessTags: $showQuantityWeaknessTags,
                    questionImageWidthPreview: $questionImageWidthPreview
                )
                LibraryErrorRelationsSection(
                    records: records,
                    draft: $draft,
                    activeRelation: $activeRelation,
                    onOpenLinkedWord: onOpenLinkedWord
                )
            }
        }
        .background(Color.white)
    }
}

private struct LibraryStandardErrorEditorForm: View {
    let recordID: String?
    let records: [StoredRecord]
    let splitMessage: String?
    let onOpenSmartSplit: () -> Void
    let onQuestionImageWidth: (String) -> Double
    let questionImageWidthBinding: (String) -> Binding<Double>
    let onCommitQuestionImageWidth: (String) -> Void
    @Binding var draft: LibraryRecordDraft
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var activeTags: ManagedTagKind?
    @Binding var activeRelation: String?
    @Binding var expandedAnswerField: ErrorAnswerField?
    @Binding var showQuantityKnowledgePoints: Bool
    @Binding var showQuantityWeaknessTags: Bool
    @Binding var questionImageWidthPreview: [String: Double]

    private var isGraphReasoning: Bool {
        draft.subject == "判断推理" && draft.module == "图形推理"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if recordID != nil {
                analysisSection
            }
            if draft.subject == "资料分析" {
                LibraryDataAnalysisMaterialSection(draft: $draft)
            }
            if !draft.images.isEmpty {
                LibraryErrorImageSection(
                    draft: $draft,
                    selectedPhotos: $selectedPhotos,
                    questionImageWidthPreview: $questionImageWidthPreview,
                    questionImageWidth: onQuestionImageWidth,
                    questionImageWidthBinding: questionImageWidthBinding,
                    onCommitQuestionImageWidth: onCommitQuestionImageWidth
                )
            }
            LibraryErrorQuestionOptionsSection(
                draft: $draft,
                isDataAnalysis: draft.subject == "资料分析",
                splitMessage: splitMessage,
                onOpenSmartSplit: onOpenSmartSplit
            )
            LibraryErrorAnswerSourceSection(
                draft: $draft,
                records: records,
                activeRelation: $activeRelation,
                expandedAnswerField: $expandedAnswerField
            )
            if isGraphReasoning {
                LibraryGraphRuleSection(draft: $draft)
            }
            if recordID == nil {
                analysisSection
            }
        }
    }

    private var analysisSection: some View {
        LibraryErrorAnalysisSection(
            records: records,
            draft: $draft,
            activeTags: $activeTags,
            showQuantityKnowledgePoints: $showQuantityKnowledgePoints,
            showQuantityWeaknessTags: $showQuantityWeaknessTags
        )
    }
}

private struct LibraryErrorQuestionOptionsSection: View {
    @Binding var draft: LibraryRecordDraft
    let isDataAnalysis: Bool
    let splitMessage: String?
    let onOpenSmartSplit: () -> Void

    var body: some View {
        formCard {
            VStack(alignment: .leading, spacing: 7) {
                Label("题目与选项", systemImage: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .medium))
                HStack {
                    NativeFieldLabel(title: "题干")
                    Spacer()
                    Button(action: onOpenSmartSplit) {
                        Label("智能拆分", systemImage: "sparkles")
                            .font(AppTheme.auxiliaryFont.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                }
                if let splitMessage {
                    Text(splitMessage)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(splitMessage.hasPrefix("已") ? AppTheme.success : AppTheme.warning)
                }
                ShenlunAdaptiveTextEditor(
                    text: $draft.title,
                    minimumHeight: 70,
                    growsWithContent: true,
                    fontSize: 15,
                    accessibilityIdentifier: "library-error-question"
                )
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
                ForEach(draft.options.indices, id: \.self) { index in
                    LibraryErrorOptionEditorRow(
                        index: index,
                        text: bindingForOption(at: index),
                        imageSource: bindingForOptionImage(at: index),
                        imageID: draft.optionImageIDs.indices.contains(index) ? draft.optionImageIDs[index] : "option-\(index)",
                        isDataAnalysis: isDataAnalysis
                    )
                }
            }
        }
    }

    private func bindingForOption(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.options.indices.contains(index) ? draft.options[index] : "" },
            set: { value in
                guard draft.options.indices.contains(index) else { return }
                draft.options[index] = value
            }
        )
    }

    private func bindingForOptionImage(at index: Int) -> Binding<String> {
        Binding(
            get: { draft.optionImages.indices.contains(index) ? draft.optionImages[index] : "" },
            set: { draft.setOptionImage($0, at: index) }
        )
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5, content: content)
            .padding(10)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryErrorOptionEditorRow: View {
    let index: Int
    @Binding var text: String
    @Binding var imageSource: String
    let imageID: String
    let isDataAnalysis: Bool

    private var letter: String { String(UnicodeScalar(65 + index)!) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: StudyOptionRowLayout.verticalAlignment(hasText: !text.isEmpty), spacing: 7) {
                Text(letter)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.accent)
                    .frame(width: 28, height: 28)
                    .background(AppTheme.accent.opacity(0.10), in: Capsule())
                    .alignmentGuide(.firstTextBaseline) { dimensions in
                        dimensions[.firstTextBaseline]
                    }
                TextField("", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .font(.system(size: 13.5, weight: .regular))
                    .padding(.horizontal, 11)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
                    .accessibilityLabel("选项 \(letter)")
                    .accessibilityIdentifier("library-error-option-\(index)")
                if isDataAnalysis {
                    DataAnalysisOptionImagePicker(hasImage: !imageSource.isEmpty) { imageSource = $0 }
                        .alignmentGuide(.firstTextBaseline) { $0[.top] + $0.height / 2 }
                }
            }
            if isDataAnalysis, !imageSource.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Color.clear.frame(width: 21, height: 1)
                    LibraryEditorImagePreview(
                        source: imageSource,
                        imageID: imageID,
                        width: nil,
                        height: 190,
                        contentMode: .fit,
                        maximumPixelSize: 1_200
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.09), lineWidth: 0.8))
                    Button { imageSource = "" } label: {
                        Image(systemName: "trash").foregroundStyle(AppTheme.danger)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("删除\(letter)选项图片")
                }
            }
        }
        .padding(.vertical, 2)
    }
}

private struct LibraryErrorImageSection: View {
    @Binding var draft: LibraryRecordDraft
    @Binding var selectedPhotos: [PhotosPickerItem]
    @Binding var questionImageWidthPreview: [String: Double]
    let questionImageWidth: (String) -> Double
    let questionImageWidthBinding: (String) -> Binding<Double>
    let onCommitQuestionImageWidth: (String) -> Void

    var body: some View {
        formCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NativeFieldLabel(title: "题干图片")
                    Spacer()
                    PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 12, matching: .images) {
                        Label("添加图片", systemImage: "photo.badge.plus").font(AppTheme.inputFont.weight(.semibold))
                    }
                }
                if !draft.imageDisplaySettings.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(draft.imageDisplaySettings) { setting in
                                if let index = draft.imageDisplaySettings.firstIndex(where: { $0.id == setting.id }), draft.images.indices.contains(index) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ZStack(alignment: .topTrailing) {
                                            LibraryEditorImagePreview(source: draft.images[index], imageID: setting.id, width: 90, height: 74)
                                            Button { draft.removeQuestionImage(at: index) } label: {
                                                Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette).foregroundStyle(.white, .black.opacity(0.55))
                                            }
                                            .buttonStyle(.plain)
                                            .offset(x: 5, y: -5)
                                        }
                                        HStack(spacing: 4) {
                                            let width = questionImageWidth(setting.id)
                                            Text("\(Int((width * 100).rounded()))%")
                                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                                .foregroundStyle(.secondary)
                                                .frame(width: 38, alignment: .leading)
                                            Slider(
                                                value: questionImageWidthBinding(setting.id),
                                                in: LibraryImageDisplaySetting.minimumWidthFraction...LibraryImageDisplaySetting.maximumWidthFraction,
                                                step: LibraryImageDisplaySetting.stepWidthFraction,
                                                onEditingChanged: { isEditing in
                                                    if !isEditing { onCommitQuestionImageWidth(setting.id) }
                                                }
                                            )
                                            .accessibilityLabel("题干图片显示宽度")
                                            Button("全宽") {
                                                draft.setQuestionImageWidth(id: setting.id, fraction: LibraryImageDisplaySetting.maximumWidthFraction)
                                                questionImageWidthPreview[setting.id] = nil
                                            }
                                            .font(.system(size: 11, weight: .medium))
                                            .buttonStyle(.plain)
                                            .foregroundStyle(AppTheme.accent)
                                            .disabled(width >= LibraryImageDisplaySetting.maximumWidthFraction)
                                        }
                                    }
                                    .frame(width: 205, alignment: .leading)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryErrorAnswerSourceSection: View {
    @Binding var draft: LibraryRecordDraft
    let records: [StoredRecord]
    @Binding var activeRelation: String?
    @Binding var expandedAnswerField: ErrorAnswerField?

    var body: some View {
        formCard {
            VStack(alignment: .leading, spacing: 7) {
                Label("答案与来源", systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .medium))
                HStack(alignment: .top, spacing: 8) {
                    answerPicker(title: "正确选项", field: .correct, selection: $draft.correctOption)
                    answerPicker(title: "我的选项", field: .selected, selection: $draft.userOption)
                }
                HStack(spacing: 8) {
                    TextField("全站正确率（%）", text: $draft.accuracy)
                        .keyboardType(.decimalPad)
                        .textFieldStyle(ErrorFormTextFieldStyle())
                    LibraryQuestionSourceRow(draft: $draft, activeRelation: $activeRelation, examTitle: sourceExamTitle, placeholder: "题目来源，例如：2024国考")
                }
            }
        }
    }

    private var sourceExamTitle: String {
        records.first { $0.collection == "exams" && $0.recordID == draft.sourceExamID }?.title ?? ""
    }

    private func answerPicker(title: String, field: ErrorAnswerField, selection: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            Button {
                withoutAnimation { expandedAnswerField = expandedAnswerField == field ? nil : field }
            } label: {
                HStack(spacing: 6) {
                    Text(selection.wrappedValue.isEmpty ? "请选择" : selection.wrappedValue)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(selection.wrappedValue.isEmpty ? Color.secondary : Color.primary)
                    Spacer()
                    Image(systemName: "chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 11)
                .frame(maxWidth: .infinity, minHeight: 38)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.12), lineWidth: 0.8))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expandedAnswerField == field {
                HStack(spacing: 5) {
                    ForEach(["A", "B", "C", "D"], id: \.self) { value in
                        Button {
                            selection.wrappedValue = value
                            withoutAnimation { expandedAnswerField = nil }
                        } label: {
                            Text(value)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(selection.wrappedValue == value ? AppTheme.accent : Color.primary)
                                .frame(maxWidth: .infinity, minHeight: 27)
                                .background(selection.wrappedValue == value ? AppTheme.accent.opacity(0.09) : Color.white, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(selection.wrappedValue == value ? AppTheme.accent.opacity(0.55) : Color.primary.opacity(0.1), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func withoutAnimation(_ changes: () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction, changes)
    }

    private func formCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6, content: content)
            .padding(14)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryQuestionSourceRow: View {
    @Binding var draft: LibraryRecordDraft
    @Binding var activeRelation: String?
    let examTitle: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 6) {
            if draft.reviewSource == .mock {
                Button {
                    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                    activeRelation = "exams"
                } label: {
                    HStack(spacing: 6) {
                        Text(draft.sourceExamID.isEmpty ? "未关联套卷" : (examTitle.isEmpty ? "未关联套卷" : examTitle))
                            .font(.system(size: 12.5))
                            .foregroundStyle(draft.sourceExamID.isEmpty ? Color.secondary : Color.primary)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, minHeight: 36)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("来源套卷")
            } else {
                TextField(placeholder, text: $draft.questionSource)
                    .textFieldStyle(ErrorFormTextFieldStyle())
            }
            TextField("题号", text: $draft.questionNumber)
                .keyboardType(.numberPad)
                .frame(width: 72)
                .textFieldStyle(ErrorFormTextFieldStyle())
        }
    }
}

private struct LibraryGraphRuleSection: View {
    @Binding var draft: LibraryRecordDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("规律与识别思路", systemImage: "eye").font(.system(size: 13, weight: .medium))
            TextField("图形规律", text: $draft.graphRule).textFieldStyle(ErrorFormTextFieldStyle())
            TextField("识别思路", text: $draft.recognition).textFieldStyle(ErrorFormTextFieldStyle())
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryDataAnalysisMaterialSection: View {
    @Binding var draft: LibraryRecordDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("材料（可选）", systemImage: "doc.text").font(.system(size: 13, weight: .medium))
            ShenlunAdaptiveTextEditor(text: $draft.dataAnalysisMaterialText, minimumHeight: 82, growsWithContent: true)
                .accessibilityIdentifier("library-data-analysis-material-editor")
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryErrorAnalysisSection: View {
    let records: [StoredRecord]
    @Binding var draft: LibraryRecordDraft
    @Binding var activeTags: ManagedTagKind?
    @Binding var showQuantityKnowledgePoints: Bool
    @Binding var showQuantityWeaknessTags: Bool

    private var isQuantity: Bool { draft.subject == "数量关系" }
    private var isDataAnalysis: Bool { draft.subject == "资料分析" }
    private var isAnalogy: Bool { draft.subject == "判断推理" && draft.module == "类比推理" }
    private var isLogicJudgment: Bool { draft.subject == "判断推理" && draft.module == "逻辑判断" }
    private var knowledgeLabel: String { isLogicJudgment ? "题干逻辑结构" : "考点" }
    private var causeLabel: String { isLogicJudgment ? "选项逻辑作用" : (isAnalogy ? "二级辨析" : "错因") }
    private var quantityErrorCause: Binding<String> {
        Binding(
            get: { draft.errorCause },
            set: {
                draft.errorCause = $0
                draft.quantityErrorCauseIsAuthoritative = true
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isQuantity {
                quantityAnalysis
            } else {
                generalAnalysis
            }
        }
    }

    private var quantityAnalysis: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("题型分析", systemImage: "tag").font(.system(size: 13, weight: .medium))
            quantityTextInput(title: "题目结构", placeholder: "例如：矩形边界植树", text: $draft.quantityStructure)
            quantityTagInput(title: "考点", value: draft.knowledgePoint) { showQuantityKnowledgePoints = true }
            tagInput(title: "错因", text: quantityErrorCause, allowsMultiple: true)
            plainTextInput(label: "提醒", text: $draft.reminder)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }

    private var generalAnalysis: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("\(knowledgeLabel)与\(causeLabel)", systemImage: "tag").font(.system(size: 13, weight: .medium))
            tagInput(title: knowledgeLabel, text: $draft.knowledgePoint, allowsMultiple: true, showsChevron: false)
            if isDataAnalysis || isAnalogy {
                plainTextInput(label: causeLabel, text: $draft.errorCause)
            } else {
                tagInput(title: causeLabel, text: $draft.errorCause, allowsMultiple: false)
            }
            plainTextInput(label: isDataAnalysis ? "陷阱" : "思维误区", text: $draft.pitfall)
            plainTextInput(label: isAnalogy ? "常识" : "提醒", text: $draft.reminder)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }

    private func tagInput(title: String, text: Binding<String>, allowsMultiple: Bool, showsChevron: Bool = true) -> some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            activeTags = allowsMultiple ? .knowledgePoint : .errorCause
        } label: {
            HStack(spacing: 8) {
                Text(title).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
                if text.wrappedValue.isEmpty {
                    Text("选择或新增").font(.system(size: 12)).foregroundStyle(.tertiary)
                    Spacer()
                } else {
                    NativeTagFlow {
                        ForEach(tagValues(text.wrappedValue, allowsMultiple: allowsMultiple), id: \.self) { value in
                            Text(value).font(.system(size: 11)).foregroundStyle(AppTheme.accent)
                                .padding(.horizontal, 7).padding(.vertical, 4)
                                .background(AppTheme.accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
                        }
                    }
                }
                if showsChevron {
                    Image(systemName: "chevron.down").font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)选择或新增")
    }

    private func tagValues(_ value: String, allowsMultiple: Bool) -> [String] {
        guard allowsMultiple else { return [value] }
        return value.split(whereSeparator: { "、,，".contains($0) }).map(String.init)
    }

    private func quantityTagInput(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                Text(value.isEmpty ? "选择或新增" : value.replacingOccurrences(of: ",", with: "、").replacingOccurrences(of: "，", with: "、"))
                    .font(.system(size: 12.5)).foregroundStyle(value.isEmpty ? Color.secondary : Color.primary).lineLimit(1)
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(minHeight: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
        }
        .buttonStyle(.plain)
    }

    private func quantityTextInput(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 9) {
            Text(title).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
            TextField(placeholder, text: text).font(.system(size: 12.5, weight: .regular))
        }
        .padding(.horizontal, 10)
        .frame(minHeight: 38)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
    }

    private func plainTextInput(label: String, text: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
            TextField("可留空", text: text, axis: .vertical)
                .font(.system(size: 12.5, weight: .regular)).lineLimit(1...5).frame(minHeight: 22)
        }
        .padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 38)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
    }
}

private struct LibraryErrorRelationsSection: View {
    let records: [StoredRecord]
    @Binding var draft: LibraryRecordDraft
    @Binding var activeRelation: String?
    let onOpenLinkedWord: (String) -> Void

    private var linkedWords: [StoredRecord] {
        let ids = Set(draft.linkedWordIDs)
        return records.filter { $0.collection == "words" && ids.contains($0.recordID) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("内容关联").font(.system(size: 11)).foregroundStyle(.secondary)
            if draft.reviewSource != .mock {
                relationButton(collection: "exams", title: "来源套卷", value: relationTitle("exams", id: draft.sourceExamID))
            }
            relationButton(collection: "notes", title: "关联笔记", value: draft.linkedNoteIDs.isEmpty ? "未关联" : "已关联 \(draft.linkedNoteIDs.count) 项")
            if draft.subject == "言语理解", draft.module == "逻辑填空" {
                linkedWordSection
            }
        }
    }

    private var linkedWordSection: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("关联词语库").font(.system(size: 12, weight: .medium))
                Spacer()
                Button { activeRelation = "words" } label: {
                    Label("筛选关联", systemImage: "plus").font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.plain)
            }
            if linkedWords.isEmpty {
                Text("尚未关联，可从词语库筛选或直接新建").font(.system(size: 11)).foregroundStyle(.tertiary)
            } else {
                ForEach(linkedWords, id: \.compoundID) { record in
                    let snapshot = LibraryRecordSnapshot(record: record)
                    Button { onOpenLinkedWord(record.recordID) } label: {
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(snapshot.title).font(.system(size: 12.5, weight: .medium)).foregroundStyle(.primary).lineLimit(1)
                                if !snapshot.summary.isEmpty {
                                    Text(snapshot.summary).font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 10).frame(minHeight: 40)
                        .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 7)
    }

    private func relationButton(collection: String, title: String, value: String) -> some View {
        Button {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
            activeRelation = collection
        } label: {
            NativeDocumentProperty(title: title, value: value)
        }
        .buttonStyle(.plain)
    }

    private func relationTitle(_ collection: String, id: String) -> String {
        guard !id.isEmpty else { return collection == "exams" ? "未关联套卷" : "未关联" }
        return records.first { $0.collection == collection && $0.recordID == id }?.title ?? "记录已不存在"
    }
}

private struct LibraryShenlunEditorForm: View {
    @Binding var draft: LibraryRecordDraft
    @Binding var activeRelation: String?
    @Binding var isCurrentAffairsSupplementExpanded: Bool
    let internalLinks: [RichTextInternalLink]
    let onOpenInternalLink: (RichTextInternalLink) -> Void
    let records: [StoredRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryShenlunSourceSection(draft: $draft, activeRelation: $activeRelation, records: records)
            LibraryShenlunCurrentAffairsSection(draft: $draft, expanded: $isCurrentAffairsSupplementExpanded)
            LibraryShenlunTextSection(title: "我的作答", image: "pencil.line", text: $draft.myAnswer)
            LibraryShenlunTextSection(title: "参考答案", image: "checkmark.document", text: $draft.referenceAnswer)
            LibraryShenlunTextSection(title: "我的作答问题（可选）", image: "exclamationmark.bubble", text: $draft.myAnswerIssues)
            LibraryShenlunReminderSection(text: $draft.reminder)
            LibraryShenlunTextSection(title: "材料分析（可选）", image: "doc.text.magnifyingglass", text: $draft.materialsAnalysis)
            LibraryShenlunRichNoteSection(text: $draft.content, internalLinks: internalLinks, onOpenInternalLink: onOpenInternalLink)
            LibraryShenlunMaterialsSection(materials: $draft.materials)
            LibraryShenlunTextSection(title: "题干", image: "text.alignleft", text: $draft.title)
        }
    }
}

private struct LibraryShenlunSourceSection: View {
    @Binding var draft: LibraryRecordDraft
    @Binding var activeRelation: String?
    let records: [StoredRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("题型及来源", systemImage: "doc.text.magnifyingglass").font(.system(size: 13, weight: .medium))
            HStack(spacing: 8) {
                LibraryQuestionSourceRow(
                    draft: $draft,
                    activeRelation: $activeRelation,
                    examTitle: records.first { $0.collection == "exams" && $0.recordID == draft.sourceExamID }?.title ?? "",
                    placeholder: "题目来源（可选，如：2025国考申论）"
                )
            }
            HStack(spacing: 8) {
                TextField("得分（可选）", text: $draft.score).keyboardType(.numberPad).textFieldStyle(ErrorFormTextFieldStyle())
                TextField("总分（可选）", text: $draft.totalScore).keyboardType(.numberPad).textFieldStyle(ErrorFormTextFieldStyle())
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunCurrentAffairsSection: View {
    @Binding var draft: LibraryRecordDraft
    @Binding var expanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("时政补充（可选）", systemImage: "text.book.closed").font(.system(size: 13, weight: .medium))
            DisclosureGroup(isExpanded: $expanded) {
                ShenlunAdaptiveTextEditor(text: $draft.currentAffairsSupplement, minimumHeight: 82, growsWithContent: true)
            } label: {
                Text(draft.currentAffairsSupplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "点击填写" : "已填写")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(draft.currentAffairsSupplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .secondary : AppTheme.accent)
            }
            .tint(AppTheme.accent)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunTextSection: View {
    let title: String
    let image: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: image).font(.system(size: 13, weight: .medium))
            ShenlunAdaptiveTextEditor(text: $text, minimumHeight: 82, growsWithContent: true)
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunReminderSection: View {
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("提醒（可选）", systemImage: "lightbulb").font(.system(size: 13, weight: .medium))
            HStack(spacing: 8) {
                Text("提醒").font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 66, alignment: .leading)
                TextField("可留空", text: $text, axis: .vertical).font(.system(size: 12.5)).lineLimit(1...5)
            }
            .padding(.horizontal, 10).padding(.vertical, 8).frame(minHeight: 38)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.1), lineWidth: 0.7))
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunRichNoteSection: View {
    @Binding var text: String
    let internalLinks: [RichTextInternalLink]
    let onOpenInternalLink: (RichTextInternalLink) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("复盘笔记（可选）", systemImage: "note.text").font(.system(size: 13, weight: .medium))
            NativeRichTextEditor(html: $text, minHeight: 220, documentStyle: true, internalLinks: internalLinks, onOpenInternalLink: onOpenInternalLink)
                .padding(8)
                .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(Color.primary.opacity(0.11), lineWidth: 0.8))
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunMaterialsSection: View {
    @Binding var materials: [ShenlunMaterialDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label("材料（可选）", systemImage: "doc.on.doc").font(.system(size: 13, weight: .medium))
            HStack {
                Spacer()
                Button { materials.append(.init()) } label: {
                    Label("增加材料", systemImage: "plus").font(AppTheme.auxiliaryFont.weight(.semibold))
                }
                .buttonStyle(.plain)
            }
            ForEach(materials, id: \.id) { material in
                if let index = materials.firstIndex(where: { $0.id == material.id }) {
                LibraryShenlunMaterialRow(
                    index: index,
                    count: materials.count,
                    text: $materials[index].content,
                    onRemove: {
                        guard materials.count > 1,
                              let currentIndex = materials.firstIndex(where: { $0.id == material.id })
                        else { return }
                        materials.remove(at: currentIndex)
                    }
                )
                }
            }
        }
        .padding(14)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color(red: 0.88, green: 0.88, blue: 0.88), lineWidth: 0.8))
    }
}

private struct LibraryShenlunMaterialRow: View {
    let index: Int
    let count: Int
    @Binding var text: String
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                NativeFieldLabel(title: "材料 \(index + 1)")
                Spacer()
                if count > 1 {
                    Button("删除", action: onRemove).font(AppTheme.auxiliaryFont).foregroundStyle(AppTheme.danger).buttonStyle(.plain)
                }
            }
            ShenlunAdaptiveTextEditor(text: $text, minimumHeight: 170, growsWithContent: false)
        }
        .padding(.vertical, 4)
    }
}
