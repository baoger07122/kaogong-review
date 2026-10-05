import SwiftUI
import SwiftData
import UIKit

struct QuestionBankReadingStep: Identifiable, Equatable {
    enum Kind: Equatable {
        case material(String)
        case question(String)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .material(let id): "material:\(id)"
        case .question(let id): "question:\(id)"
        }
    }
}

enum QuestionBankReadingSequence {
    static func steps(for questions: [QuestionBankQuestion]) -> [QuestionBankReadingStep] {
        let orderedQuestions = questions.sorted {
            if $0.number != $1.number { return $0.number < $1.number }
            return $0.id < $1.id
        }
        var emittedMaterialIDs = Set<String>()
        var result: [QuestionBankReadingStep] = []
        result.reserveCapacity(orderedQuestions.count * 2)

        for question in orderedQuestions {
            if !question.materialID.isEmpty, emittedMaterialIDs.insert(question.materialID).inserted {
                result.append(QuestionBankReadingStep(kind: .material(question.materialID)))
            }
            result.append(QuestionBankReadingStep(kind: .question(question.id)))
        }
        return result
    }
}

struct QuestionBankQuestionRouteTarget: Equatable {
    let moduleID: String
    let questionNumber: Int
}

enum QuestionBankQuestionRoute {
    static func target(
        questionNumber: Int?,
        paperID: String,
        selectedModuleTitle: String,
        records: [QuestionBankRecord]
    ) -> QuestionBankQuestionRouteTarget? {
        guard let questionNumber, questionNumber > 0 else { return nil }
        let candidates = records
            .filter {
                $0.paperID == paperID && $0.kind == QuestionBankRepository.questionKind
                    && $0.questionNumber == questionNumber
            }
            .sorted { $0.stableID < $1.stableID }
        for question in candidates {
            guard let moduleID = question.moduleID, !moduleID.isEmpty else { continue }
            if !selectedModuleTitle.isEmpty {
                let moduleMatchesFilter = records.contains {
                    $0.paperID == paperID && $0.kind == QuestionBankRepository.moduleKind
                        && $0.stableID == moduleID && $0.title == selectedModuleTitle
                }
                guard moduleMatchesFilter else { continue }
            }
            return QuestionBankQuestionRouteTarget(moduleID: moduleID, questionNumber: questionNumber)
        }
        return nil
    }
}

struct QuestionBankOverviewItem: Identifiable, Equatable {
    let id: String
    let number: Int
    let materialID: String
}

private struct QuestionBankReadingItem: Identifiable {
    let record: QuestionBankRecord
    let question: QuestionBankQuestion

    var id: String { record.stableID }
    var overviewItem: QuestionBankOverviewItem {
        QuestionBankOverviewItem(id: id, number: question.number, materialID: question.materialID)
    }
}

private struct QuestionBankReaderSheet: Identifiable {
    enum Content {
        case overview
        case material(String)
    }

    let content: Content

    var id: String {
        switch content {
        case .overview: "question-overview"
        case .material(let id): "material-panel:\(id)"
        }
    }
}

private struct QuestionBankScrollRequest: Equatable {
    let questionID: String
    let token: UUID
}

private struct QuestionBankReaderViewportFrame: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

private struct QuestionBankReaderViewportPreference: PreferenceKey {
    static var defaultValue: [String: QuestionBankReaderViewportFrame] = [:]

    static func reduce(
        value: inout [String: QuestionBankReaderViewportFrame],
        nextValue: () -> [String: QuestionBankReaderViewportFrame]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

struct QuestionBankModuleView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Query private var records: [QuestionBankRecord]

    let paperID: String
    let moduleID: String
    let initialQuestionNumber: String

    @State private var readingItems: [QuestionBankReadingItem] = []
    @State private var readingSteps: [QuestionBankReadingStep] = []
    @State private var materialsByID: [String: QuestionBankMaterial] = [:]
    @State private var assetsByID: [String: QuestionBankRecord] = [:]
    @State private var activeSheet: QuestionBankReaderSheet?
    @State private var splitMaterialID: String?
    @State private var currentVisibleQuestionID: String?
    @State private var continuousAnchorQuestionID: String?
    @State private var pendingOverviewQuestionID: String?
    @State private var continuousScrollRequest: QuestionBankScrollRequest?
    @State private var splitScrollRequest: QuestionBankScrollRequest?
    @State private var snapshotRevision = 0
    @State private var didApplyInitialFocus = false

    init(paperID: String, moduleID: String, initialQuestionNumber: String) {
        self.paperID = paperID
        self.moduleID = moduleID
        self.initialQuestionNumber = initialQuestionNumber
    }

    private var paper: QuestionBankPaper? {
        records.first { $0.paperID == paperID && $0.kind == QuestionBankRepository.paperKind }?
            .decoded(QuestionBankPaper.self)
    }

    private var module: QuestionBankModule? {
        records.first {
            $0.paperID == paperID && $0.stableID == moduleID && $0.kind == QuestionBankRepository.moduleKind
        }?.decoded(QuestionBankModule.self)
    }

    private var initialFocusQuestionID: String? {
        guard let number = Int(initialQuestionNumber), number > 0 else { return nil }
        return readingItems.first { $0.question.number == number }?.id
    }

    private var overviewItems: [QuestionBankOverviewItem] {
        readingItems.map(\.overviewItem)
    }

    var body: some View {
        GeometryReader { geometry in
            let canUseSplitLayout = horizontalSizeClass == .regular && geometry.size.width >= 860
            Group {
                if canUseSplitLayout, let splitMaterialID {
                    splitReader(materialID: splitMaterialID, width: geometry.size.width)
                } else {
                    continuousReader(isWide: canUseSplitLayout)
                }
            }
            .onChange(of: canUseSplitLayout) { _, canUseSplitLayout in
                if !canUseSplitLayout, splitMaterialID != nil {
                    closeSplitReader()
                }
            }
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle(module?.title ?? "模块阅读")
        .navigationBarTitleDisplayMode(.inline)
        .secondaryPageTabBarHidden()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    activeSheet = QuestionBankReaderSheet(content: .overview)
                } label: {
                    Label("题号卡", systemImage: "square.grid.3x3")
                }
                .disabled(readingItems.isEmpty)
                .accessibilityIdentifier("question-bank-number-overview")
            }
        }
        .sheet(item: $activeSheet, onDismiss: handleReaderSheetDismissal) { sheet in
            switch sheet.content {
            case .overview:
                QuestionBankQuestionOverviewSheet(
                    items: overviewItems,
                    currentQuestionID: currentVisibleQuestionID,
                    onSelect: handleOverviewSelection
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            case .material(let materialID):
                materialPanel(for: materialID)
            }
        }
        .onAppear(perform: refreshReaderSnapshot)
        .onChange(of: records.count) { _, _ in refreshReaderSnapshot() }
        .onChange(of: snapshotRevision) { _, _ in applyInitialFocusIfNeeded() }
    }

    @ViewBuilder
    private func continuousReader(isWide: Bool) -> some View {
        if readingItems.isEmpty {
            emptyModuleState
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        readerContext
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(readingSteps) { step in
                                switch step.kind {
                                case .material(let materialID):
                                    if let material = materialsByID[materialID] {
                                        materialSection(material, isWide: isWide)
                                            .id(step.id)
                                    }
                                case .question(let questionID):
                                    if let item = readingItem(for: questionID) {
                                        questionSection(item)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                }
                .coordinateSpace(name: "question-bank-continuous-scroll")
                .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                .onChange(of: continuousScrollRequest) { _, request in
                    guard request != nil else { return }
                    consumeContinuousScrollRequest(using: proxy)
                }
                .onAppear { consumeContinuousScrollRequest(using: proxy) }
            }
        }
    }

    @ViewBuilder
    private func splitReader(materialID: String, width: CGFloat) -> some View {
        if let material = materialsByID[materialID] {
            let groupedQuestions = readingItems.filter { $0.question.materialID == materialID }
            let leftWidth = min(max(width * 0.40, 300), width - 480)
            VStack(spacing: 0) {
                readerContext
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        HStack {
                            Text("共用材料").font(AppTheme.sectionTitleFont)
                            Spacer(minLength: 8)
                            Button(action: closeSplitReader) {
                                Label("关闭分屏", systemImage: "rectangle.split.2x1")
                                    .font(AppTheme.auxiliaryFont.weight(.medium))
                            }
                            .accessibilityIdentifier("question-bank-close-material-split")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        Divider()
                        ScrollView {
                            QuestionBankMaterialBody(
                                material: material,
                                imageAsset: assetRecord(for: material.imageAssetID),
                                showsHeading: false
                            )
                            .padding(16)
                        }
                    }
                    .frame(width: leftWidth)
                    .frame(maxHeight: .infinity)

                    Rectangle()
                        .fill(Color(uiColor: .separator).opacity(0.6))
                        .frame(width: 1)

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(groupedQuestions) { item in
                                    questionSection(item)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                        }
                        .coordinateSpace(name: "question-bank-continuous-scroll")
                        .onPreferenceChange(QuestionBankReaderViewportPreference.self, perform: updateVisibleQuestion)
                        .onChange(of: splitScrollRequest) { _, request in
                            guard let request else { return }
                            withAnimation(.easeInOut(duration: 0.25)) {
                                proxy.scrollTo(request.questionID, anchor: .top)
                            }
                        }
                        .onAppear {
                            let target = splitScrollRequest?.questionID
                                ?? groupedQuestions.first?.id
                            if let target {
                                Task { @MainActor in
                                    await Task.yield()
                                    proxy.scrollTo(target, anchor: .top)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            emptyModuleState
        }
    }

    private var readerContext: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let paper {
                Text("\(String(paper.year)) · \(paper.examType) · \(paper.title)")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let instruction = module?.instruction, !instruction.isEmpty {
                Text(instruction)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    private var emptyModuleState: some View {
        Group {
            if module == nil {
                NativeStatusCard(
                    title: "模块不存在",
                    detail: "此模块可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            } else {
                NativeStatusCard(
                    title: "本次样本未收录题目",
                    detail: "该模块已保留在试卷结构中，当前导入样本没有可阅读的题目。",
                    systemImage: "doc.text.magnifyingglass",
                    color: AppTheme.accent
                )
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func materialSection(_ material: QuestionBankMaterial, isWide: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text("共用材料")
                    .font(AppTheme.sectionTitleFont)
                if !material.type.isEmpty {
                    Text(material.type)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button {
                    openMaterial(material.id, isWide: isWide)
                } label: {
                    Label("分屏看材料", systemImage: "rectangle.split.2x1")
                        .font(AppTheme.auxiliaryFont.weight(.medium))
                }
                .accessibilityIdentifier("question-bank-split-material-\(material.id)")
            }
            QuestionBankMaterialBody(
                material: material,
                imageAsset: assetRecord(for: material.imageAssetID),
                showsHeading: false
            )
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
    }

    private func questionSection(_ item: QuestionBankReadingItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("第\(String(item.question.number))题")
                    .font(AppTheme.sectionTitleFont.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                let subject = item.question.type.isEmpty ? item.question.subject : item.question.type
                if !subject.isEmpty {
                    Text(subject)
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 9)

            if !item.question.stem.isEmpty {
                Text(item.question.stem)
                    .font(AppTheme.questionTextFont)
                    .lineSpacing(AppTheme.questionLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }
            if !item.question.stemImageAssetID.isEmpty,
               let asset = assetRecord(for: item.question.stemImageAssetID) {
                QuestionBankLocalImage(asset: asset)
                    .padding(.bottom, 10)
            }

            ForEach(item.question.options) { option in
                QuestionBankOptionRow(
                    option: option,
                    answer: item.question.answer,
                    assetLookup: assetRecord(for:)
                )
            }

            HStack(spacing: 7) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                Text("正确答案")
                    .foregroundStyle(.secondary)
                Text(item.question.answer.isEmpty ? "未提供" : item.question.answer)
                    .fontWeight(.semibold)
                    .foregroundStyle(AppTheme.success)
            }
            .font(AppTheme.bodyFont)
            .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 18)
        .background {
            GeometryReader { geometry in
                let frame = geometry.frame(in: .named("question-bank-continuous-scroll"))
                Color.clear.preference(
                    key: QuestionBankReaderViewportPreference.self,
                    value: [item.id: QuestionBankReaderViewportFrame(top: frame.minY, bottom: frame.maxY)]
                )
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.45))
                .frame(height: 1)
        }
        .id(item.id)
        .accessibilityIdentifier("question-bank-question-\(item.id)")
    }

    private func openMaterial(_ materialID: String, isWide: Bool) {
        guard isWide else {
            activeSheet = QuestionBankReaderSheet(content: .material(materialID))
            return
        }
        continuousAnchorQuestionID = currentVisibleQuestionID
        splitMaterialID = materialID
        let preferredQuestion = readingItems.first {
            $0.id == currentVisibleQuestionID && $0.question.materialID == materialID
        }
        let target = preferredQuestion?.id ?? readingItems.first { $0.question.materialID == materialID }?.id
        if let target { splitScrollRequest = QuestionBankScrollRequest(questionID: target, token: UUID()) }
    }

    private func closeSplitReader() {
        let returnTarget = continuousAnchorQuestionID ?? currentVisibleQuestionID
        splitMaterialID = nil
        guard let returnTarget else { return }
        continuousScrollRequest = QuestionBankScrollRequest(questionID: returnTarget, token: UUID())
    }

    private func materialPanel(for materialID: String) -> some View {
        Group {
            if let material = materialsByID[materialID] {
                NavigationStack {
                    ScrollView {
                        QuestionBankMaterialBody(
                            material: material,
                            imageAsset: assetRecord(for: material.imageAssetID),
                            showsHeading: true
                        )
                        .padding(20)
                    }
                    .background(AppTheme.groupedBackground)
                    .navigationTitle("共用材料")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("完成") { activeSheet = nil }
                        }
                    }
                }
            } else {
                NativeStatusCard(
                    title: "材料不存在",
                    detail: "该材料可能已被试卷替换。",
                    systemImage: "exclamationmark.triangle",
                    color: AppTheme.warning
                )
            }
        }
    }

    private func handleOverviewSelection(_ item: QuestionBankOverviewItem) {
        pendingOverviewQuestionID = item.id
        continuousAnchorQuestionID = item.id
        if splitMaterialID != nil {
            splitMaterialID = item.materialID.isEmpty ? nil : item.materialID
        }
    }

    private func handleReaderSheetDismissal() {
        guard let questionID = pendingOverviewQuestionID else { return }
        pendingOverviewQuestionID = nil
        let request = QuestionBankScrollRequest(questionID: questionID, token: UUID())
        if splitMaterialID == nil {
            continuousScrollRequest = request
        } else {
            splitScrollRequest = request
        }
    }

    private func updateVisibleQuestion(_ frames: [String: QuestionBankReaderViewportFrame]) {
        guard let visible = frames
            .filter({ $0.value.bottom > 1 })
            .min(by: { $0.value.top < $1.value.top })?.key else { return }
        currentVisibleQuestionID = visible
        if splitMaterialID == nil { continuousAnchorQuestionID = visible }
    }

    private func applyInitialFocusIfNeeded() {
        guard !didApplyInitialFocus, let questionID = initialFocusQuestionID else { return }
        didApplyInitialFocus = true
        currentVisibleQuestionID = questionID
        continuousAnchorQuestionID = questionID
        continuousScrollRequest = QuestionBankScrollRequest(questionID: questionID, token: UUID())
    }

    private func consumeContinuousScrollRequest(using proxy: ScrollViewProxy) {
        guard let request = continuousScrollRequest else { return }
        continuousScrollRequest = nil
        Task { @MainActor in
            await Task.yield()
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(request.questionID, anchor: .top)
            }
        }
    }

    private func refreshReaderSnapshot() {
        let questions = records
            .filter {
                $0.paperID == paperID && $0.moduleID == moduleID
                    && $0.kind == QuestionBankRepository.questionKind
            }
            .compactMap { record -> QuestionBankReadingItem? in
                guard let question = record.decoded(QuestionBankQuestion.self) else { return nil }
                return QuestionBankReadingItem(record: record, question: question)
            }
            .sorted {
                if $0.question.number != $1.question.number { return $0.question.number < $1.question.number }
                return $0.id < $1.id
            }
        readingItems = questions
        readingSteps = QuestionBankReadingSequence.steps(for: questions.map(\.question))
        materialsByID = Dictionary(
            records
                .filter {
                    $0.paperID == paperID && $0.moduleID == moduleID
                        && $0.kind == QuestionBankRepository.materialKind
                }
                .compactMap { record -> (String, QuestionBankMaterial)? in
                    guard let material = record.decoded(QuestionBankMaterial.self) else { return nil }
                    return (record.stableID, material)
                },
            uniquingKeysWith: { first, _ in first }
        )
        assetsByID = Dictionary(
            records
                .filter { $0.paperID == paperID && $0.kind == QuestionBankRepository.assetKind }
                .map { ($0.stableID, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        snapshotRevision += 1
    }

    private func readingItem(for id: String) -> QuestionBankReadingItem? {
        readingItems.first { $0.id == id }
    }

    private func assetRecord(for id: String) -> QuestionBankRecord? {
        guard !id.isEmpty else { return nil }
        return assetsByID[id]
    }
}

private struct QuestionBankQuestionOverviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let items: [QuestionBankOverviewItem]
    let currentQuestionID: String?
    let onSelect: (QuestionBankOverviewItem) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 54), spacing: 10)], spacing: 10) {
                    ForEach(items) { item in
                        let isCurrent = item.id == currentQuestionID
                        Button {
                            onSelect(item)
                            dismiss()
                        } label: {
                            Text(String(item.number))
                                .font(AppTheme.bodyFont.weight(isCurrent ? .semibold : .medium))
                                .foregroundStyle(isCurrent ? AppTheme.accent : .primary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(
                                    isCurrent ? AppTheme.accent.opacity(0.12) : AppTheme.secondaryBackground,
                                    in: RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                                )
                                .overlay {
                                    RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                                        .strokeBorder(
                                            isCurrent ? AppTheme.accent : Color(uiColor: .separator).opacity(0.35),
                                            lineWidth: isCurrent ? 1.5 : 0.7
                                        )
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("第\(String(item.number))题")
                        .accessibilityIdentifier("question-bank-number-card-\(item.number)")
                    }
                }
                .padding(20)
            }
            .background(AppTheme.groupedBackground)
            .navigationTitle("题目总览")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

private struct QuestionBankMaterialBody: View {
    let material: QuestionBankMaterial
    let imageAsset: QuestionBankRecord?
    var showsHeading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if showsHeading {
                HStack(spacing: 8) {
                    Text("共用材料").font(AppTheme.sectionTitleFont)
                    if !material.type.isEmpty {
                        Text(material.type).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                    }
                }
            }
            if !material.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(material.text)
                    .font(AppTheme.bodyFont)
                    .lineSpacing(AppTheme.inputLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let imageAsset {
                QuestionBankLocalImage(asset: imageAsset)
            }
            if material.text.isEmpty && material.imageAssetID.isEmpty {
                Text("本材料暂无可显示内容")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuestionBankOptionRow: View {
    let option: QuestionBankOption
    let answer: String
    let assetLookup: (String) -> QuestionBankRecord?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(option.id)
                .font(AppTheme.bodyFont.weight(.semibold))
                .foregroundStyle(answer == option.id ? AppTheme.success : AppTheme.accent)
                .frame(width: 24, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                if !option.text.isEmpty {
                    Text(option.text)
                        .font(AppTheme.bodyFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !option.imageAssetID.isEmpty, let asset = assetLookup(option.imageAssetID) {
                    QuestionBankLocalImage(asset: asset)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if answer == option.id {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel("正确选项")
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color(uiColor: .separator).opacity(0.35))
                .frame(height: 0.7)
        }
    }
}

private struct QuestionBankLocalImage: View {
    let asset: QuestionBankRecord

    @State private var image: UIImage?
    @State private var failedToLoad = false
    @State private var enlargedImage: QuestionBankImageSelection?

    var body: some View {
        Group {
            if let image {
                Button {
                    enlargedImage = QuestionBankImageSelection(id: asset.stableID, image: image)
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("放大查看图片")
            } else if failedToLoad {
                Label("图片无法读取", systemImage: "exclamationmark.triangle")
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            } else {
                RoundedRectangle(cornerRadius: AppTheme.controlRadius)
                    .fill(AppTheme.secondaryBackground)
                    .overlay { ProgressView().controlSize(.small) }
                    .frame(height: 72)
            }
        }
        .task(id: asset.assetRelativePath) {
            image = nil
            failedToLoad = false
            guard let url = QuestionBankAssetStore.url(for: asset.assetRelativePath) else {
                failedToLoad = true
                return
            }
            let data = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url, options: [.mappedIfSafe])
            }.value
            guard let data, let decodedImage = UIImage(data: data) else {
                failedToLoad = true
                return
            }
            image = decodedImage
        }
        .fullScreenCover(item: $enlargedImage) { selection in
            QuestionBankImageZoomView(image: selection.image)
        }
    }
}

private struct QuestionBankImageSelection: Identifiable {
    let id: String
    let image: UIImage
}

private struct QuestionBankImageZoomView: View {
    @Environment(\.dismiss) private var dismiss
    let image: UIImage

    @State private var scale: CGFloat = 1
    @State private var settledScale: CGFloat = 1

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Color.black
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(
                            width: geometry.size.width * scale,
                            height: geometry.size.height * scale
                        )
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scale = scale > 1 ? 1 : 2
                                settledScale = scale
                            }
                        }
                }
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { value in
                            scale = min(6, max(1, settledScale * value.magnification))
                        }
                        .onEnded { _ in settledScale = scale }
                )
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .accessibilityLabel("关闭图片")
                .padding(.top, geometry.safeAreaInsets.top + 10)
                .padding(.trailing, 18)
            }
            .ignoresSafeArea()
        }
        .background(.black)
    }
}

extension QuestionBankRecord {
    func decoded<Value: Decodable>(_ type: Value.Type) -> Value? {
        try? JSONDecoder().decode(type, from: payload)
    }
}
