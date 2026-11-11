import ImageIO
import SwiftUI
import UIKit

struct LibrarySidebar: View {
    let records: [StoredRecord]
    @Binding var scope: LibraryScope
    @Binding var expandedSubject: String?
    let compact: Bool
    let onScopeChanged: () -> Void
    @State private var reviewSourceCache = LibraryReviewSourceClassificationCache()

    var body: some View {
        let reviewSources = reviewSourceCache.classifications(for: records)
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                if compact {
                    Color.clear.frame(height: 8)
                } else {
                    Text("学习库")
                        .font(AppTheme.pageTitleFont)
                        .padding(.horizontal, 12)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                }

                Button {
                    scope = LibraryScope(reviewSource: scope.reviewSource)
                    expandedSubject = nil
                    onScopeChanged()
                } label: {
                    sidebarRow(
                        title: "全部",
                        systemImage: "tray.full.fill",
                        color: AppTheme.accent,
                        count: records.filter { ["errors", "notes", "stickies"].contains($0.collection) && reviewSources[$0.compoundID] == scope.reviewSource }.count,
                        selected: scope.isAll,
                        showsArrow: false,
                        expanded: false
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("library-scope-all")

                ForEach(SubjectDefinition.all) { subject in
                    subjectSection(subject, reviewSources: reviewSources)
                }
            }
            .padding(.horizontal, 7)
            .padding(.bottom, 24)
        }
        .background(AppTheme.secondaryBackground.opacity(0.72))
    }

    @ViewBuilder
    private func subjectSection(
        _ subject: SubjectDefinition,
        reviewSources: [String: LibraryReviewSource]
    ) -> some View {
        let expanded = expandedSubject == subject.name
        let selected = scope.subject == subject.name && scope.module == nil

        Button {
            scope.subject = subject.name
            scope.module = nil
            if subject.isFlat {
                expandedSubject = nil
            } else {
                expandedSubject = expanded ? nil : subject.name
            }
            onScopeChanged()
        } label: {
            sidebarRow(
                title: subject.name,
                systemImage: subject.systemImage,
                color: subject.color,
                count: count(subject: subject.name, reviewSources: reviewSources),
                selected: selected,
                showsArrow: !subject.isFlat,
                expanded: expanded
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("library-subject-\(subject.name)")

        if expanded && !subject.isFlat {
            VStack(spacing: 1) {
                ForEach(subject.modules, id: \.self) { module in
                    Button {
                        scope = LibraryScope(subject: subject.name, module: module, reviewSource: scope.reviewSource)
                        onScopeChanged()
                    } label: {
                        Group {
                            if compact {
                                VStack(spacing: 2) {
                                    Text(module)
                                        .font(.system(size: 11, weight: scope.subject == subject.name && scope.module == module ? .semibold : .regular))
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.72)
                                    let moduleCount = count(subject: subject.name, module: module, reviewSources: reviewSources)
                                    if moduleCount > 0 {
                                        Text("\(moduleCount)").font(.system(size: 8)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                            } else {
                                HStack(spacing: 8) {
                                    Text(module)
                                        .font(.system(size: 12, weight: scope.subject == subject.name && scope.module == module ? .semibold : .regular))
                                        .lineLimit(1)
                                    Spacer(minLength: 4)
                                    let moduleCount = count(subject: subject.name, module: module, reviewSources: reviewSources)
                                    if moduleCount > 0 {
                                        Text("\(moduleCount)")
                                            .font(AppTheme.auxiliaryFont.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.leading, 42)
                                .padding(.trailing, 12)
                            }
                        }
                        .foregroundStyle(scope.subject == subject.name && scope.module == module ? AppTheme.accent : Color.primary)
                        .frame(height: compact ? 36 : 34)
                        .background(
                            scope.subject == subject.name && scope.module == module ? AppTheme.accent.opacity(0.09) : Color.white.opacity(0.82),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .stroke(scope.subject == subject.name && scope.module == module ? AppTheme.accent.opacity(0.35) : Color.primary.opacity(0.07), lineWidth: 0.7)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library-module-\(subject.name)-\(module)")
                }
                if subject.name == "资料分析" {
                    Button {
                        scope = LibraryScope(subject: subject.name, module: LibraryScope.dataAnalysisReviewBucket, reviewSource: scope.reviewSource)
                        onScopeChanged()
                    } label: {
                        HStack {
                            Text("待分类").font(.system(size: 12, weight: scope.subject == subject.name && scope.module == LibraryScope.dataAnalysisReviewBucket ? .semibold : .regular))
                            Spacer(minLength: 4)
                            let moduleCount = count(subject: subject.name, module: LibraryScope.dataAnalysisReviewBucket, reviewSources: reviewSources)
                            if moduleCount > 0 { Text("\(moduleCount)").font(AppTheme.auxiliaryFont.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                        .padding(.leading, compact ? 14 : 42)
                        .padding(.trailing, 12)
                        .frame(height: compact ? 36 : 34)
                        .foregroundStyle(scope.subject == subject.name && scope.module == LibraryScope.dataAnalysisReviewBucket ? AppTheme.accent : Color.primary)
                        .background(scope.subject == subject.name && scope.module == LibraryScope.dataAnalysisReviewBucket ? AppTheme.accent.opacity(0.09) : Color.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("包含未分类及历史资料分析模块记录")
                    .accessibilityIdentifier("library-module-资料分析-待分类")
                }
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(
        title: String,
        systemImage: String,
        color: Color,
        count: Int,
        selected: Bool,
        showsArrow: Bool,
        expanded: Bool
    ) -> some View {
        if compact {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? AppTheme.accent : color)
                Text(title)
                    .font(.system(size: 10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if count > 0 {
                    Text("\(count)").font(.system(size: 8)).foregroundStyle(.secondary)
                }
                if showsArrow {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 58)
            .padding(.vertical, 4)
            .foregroundStyle(selected ? AppTheme.accent : Color.primary)
            .background(selected ? AppTheme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .contentShape(Rectangle())
        } else {
            HStack(spacing: 9) {
                Image(systemName: systemImage)
                    .foregroundStyle(selected ? AppTheme.accent : color)
                    .frame(width: 22)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 4)
                if count > 0 {
                    Text("\(count)")
                        .font(AppTheme.auxiliaryFont.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if showsArrow {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .foregroundStyle(selected ? AppTheme.accent : Color.primary)
            .background(selected ? AppTheme.accent.opacity(0.09) : Color.clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
    }

    private func count(
        subject: String,
        module: String? = nil,
        reviewSources: [String: LibraryReviewSource]
    ) -> Int {
        records.lazy.filter {
            ["errors", "notes", "stickies"].contains($0.collection)
                && reviewSources[$0.compoundID] == scope.reviewSource
                && $0.subject == subject
                && (module == nil || LibraryScope(subject: subject, module: module, reviewSource: scope.reviewSource).contains($0))
        }.count
    }
}

struct LibraryRecordCard: View {
    let snapshot: LibraryRecordSnapshot
    let kind: LibraryContentKind
    let size: LibraryCardSize
    var hiddenTags: Set<String> = []

    @ViewBuilder
    var body: some View {
        if kind == .stickies {
            let sticky = HomeSticky(
                id: snapshot.record.recordID,
                content: snapshot.stickyContent,
                tag: snapshot.stickyTag,
                colorHex: snapshot.colorHex ?? "#FFFFFF",
                isPinned: snapshot.isPinned,
                createdAt: snapshot.createdAt ?? .distantPast,
                updatedAt: snapshot.record.updatedAt ?? snapshot.createdAt ?? .distantPast
            )
            StickyCardSurface(sticky: sticky) {
                Text(StickyTextPresentation.preview(snapshot.stickyContent))
                    .font(AppTheme.bodyFont)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            } headerAccessory: {
                EmptyView()
            }
        } else {
            standardCard
        }
    }

    private var standardCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            if kind == .errors {
                HStack(spacing: 5) {
                    Label((snapshot.record.module?.isEmpty == false ? snapshot.record.module : snapshot.record.subject) ?? "未分类", systemImage: "square.grid.2x2")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }
            }
            if kind != .words {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let firstTag = visibleTags.first, !(kind == .words && isComparisonRecord) {
                    Text(firstTag)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(tint.opacity(0.10), in: Capsule())
                } else if let status = snapshot.status, !status.isEmpty {
                    Text(status)
                        .font(AppTheme.auxiliaryFont.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Spacer()
                if let date = snapshot.createdAt, !(kind == .words && isComparisonRecord) {
                    Text(Self.cardDateFormatter.string(from: date))
                        .font(AppTheme.auxiliaryFont)
                        .foregroundStyle(.tertiary)
                }
                }
            }

            Text(snapshot.title)
                .font(AppTheme.bodyFont)
                .foregroundStyle(.primary)
                .lineLimit(kind == .errors ? 5 : (kind == .words ? size.questionLineLimit : 3))

            if isQuantityRelations, !snapshot.quantityStructure.isEmpty {
                quantityPlainField(label: "结构", value: snapshot.quantityStructure)
            }
            if isQuantityRelations, !snapshot.knowledgePoints.isEmpty {
                quantityTagLine(label: "考点", values: snapshot.knowledgePoints)
            }

            if kind == .words, !snapshot.wordCardBody.isEmpty, snapshot.wordCardBody != snapshot.title {
                Text(verbatim: LibraryWordCardPreviewText.render(snapshot.wordCardBody))
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(size.questionLineLimit)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !snapshot.summary.isEmpty && snapshot.summary != snapshot.title {
                Text(snapshot.summary)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
            }

            if kind != .words, visibleTags.count > 1 {
                Text(visibleTags.dropFirst().joined(separator: " · "))
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                .stroke(Color.primary.opacity(0.055), lineWidth: 0.6)
        }
    }

    private var visibleTags: [String] {
        snapshot.tags.filter {
            !hiddenTags.contains($0) && (!isQuantityRelations || !snapshot.knowledgePoints.contains($0))
        }
    }

    private var isComparisonRecord: Bool {
        WordCategory(rawValue: snapshot.category)?.isComparison == true
    }

    private var isQuantityRelations: Bool { snapshot.record.subject == "数量关系" }

    private func quantityPlainField(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("\(label)：").font(.system(size: 11, weight: .medium))
            Text(value).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    private func quantityTagLine(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("\(label)：").font(.system(size: 11, weight: .medium)).padding(.top, 3)
            NativeTagFlow(spacing: 5) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(AppTheme.accent)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(AppTheme.accent.opacity(0.09), in: Capsule())
                }
            }
        }
    }

    private static let cardDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月d日"
        return formatter
    }()

    private var tint: Color {
        switch kind {
        case .errors: AppTheme.danger
        case .notes: AppTheme.accent
        case .stickies: .orange
        case .words: .purple
        }
    }

    private var cardBackground: Color {
        guard kind == .stickies, let value = snapshot.colorHex else { return AppTheme.secondaryBackground }
        return Color(homeHex: value).opacity(0.26)
    }
}

private struct LibraryErrorCardWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let next = nextValue()
        if next > 0 { value = next }
    }
}

private struct LibraryErrorRecordCard: View {
    let snapshot: LibraryRecordSnapshot
    let size: LibraryCardSize
    let hidesQuantityTypeLabel: Bool
    @State private var cardWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            questionKnowledgeHeader
            if isLogicFill, !displayedLogicComparisonGroups.isEmpty {
                logicComparisonLine
            }

            if isDataAnalysisComposite, !snapshot.dataAnalysisMaterialText.isEmpty {
                Text(snapshot.dataAnalysisMaterialText)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundStyle(.secondary)
                    .lineSpacing(1.5)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            images

            Text(isLogicFill ? LibraryLogicComparisonLayout.preview(snapshot.title) : snapshot.title)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(Color.primary)
                .lineSpacing(2.5)
                .lineLimit(isDataAnalysisComposite ? 2 : size.questionLineLimit)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !isDataAnalysisComposite, isAnalogyReasoning, !snapshot.options.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(snapshot.options.enumerated()), id: \.offset) { index, option in
                        Text("\(String(UnicodeScalar(65 + index)!)).  \(option)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.primary)
                            .lineSpacing(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                if isQuantityRelations, !snapshot.quantityStructure.isEmpty {
                    plainField(label: "结构", value: snapshot.quantityStructure)
                }

                if !snapshot.comparisonWords.isEmpty, !isLogicFill {
                    tagLine(
                        label: "辨析",
                        values: snapshot.comparisonWords,
                        foreground: AppTheme.accent.opacity(0.82),
                        background: AppTheme.accent.opacity(0.06)
                    )
                }

                let causes = isDataAnalysis || isLogicFill
                    ? []
                    : (isQuantityRelations ? snapshot.quantityErrorCauses : splitTags(snapshot.errorCause))
                let dataAnalysisCauses = LibraryDataAnalysisCauseLayout.splitLines(snapshot.dataAnalysisErrorCause)
                if isDataAnalysis || isLogicFill {
                    if !dataAnalysisCauses.isEmpty {
                        sentenceTagLine(label: errorCauseLabel, values: dataAnalysisCauses)
                    }
                } else {
                    if !causes.isEmpty {
                        if isAnalogyReasoning {
                            plainField(label: errorCauseLabel, value: snapshot.errorCause)
                        } else if isQuantityRelations {
                            quantityCauseTagLine(label: errorCauseLabel, values: causes)
                        } else {
                            tagLine(
                                label: errorCauseLabel,
                                values: causes,
                                foreground: .secondary,
                                background: Color.primary.opacity(0.045)
                            )
                        }
                    }
                }

                if !isLogicFill, !snapshot.pitfall.isEmpty {
                    pitfallLine(value: snapshot.pitfall, label: isDataAnalysis ? "陷阱" : "误区")
                }

                if !snapshot.reminder.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(isAnalogyReasoning ? "常识：" : "提醒：")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color(red: 48 / 255.0, green: 48 / 255.0, blue: 48 / 255.0))
                            .fixedSize(horizontal: true, vertical: false)
                        Text(snapshot.reminder)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color(red: 80 / 255.0, green: 80 / 255.0, blue: 80 / 255.0))
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1.5)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: isDataAnalysisComposite ? 0 : 110, alignment: .leading)
        .background {
            if isDataAnalysisComposite {
                GeometryReader { proxy in
                    Color.clear.preference(key: LibraryErrorCardWidthPreferenceKey.self, value: proxy.size.width)
                }
            }
        }
        .onPreferenceChange(LibraryErrorCardWidthPreferenceKey.self) { width in
            guard isDataAnalysisComposite else { return }
            guard width > 0, abs(width - cardWidth) > 0.5 else { return }
            cardWidth = width
        }
        .background(Color.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.065), lineWidth: 0.7)
        }
        .shadow(color: Color.black.opacity(0.04), radius: 6, y: 3)
    }

    @ViewBuilder
    private var images: some View {
        if !snapshot.imageValues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(snapshot.imageValues.prefix(isDataAnalysisComposite ? 1 : 3).enumerated()), id: \.offset) { index, source in
                    HStack(spacing: 0) {
                        LibraryCardThumbnail(
                            source: source,
                            cacheKey: snapshot.imageIdentities.indices.contains(index)
                                ? snapshot.imageIdentities[index] : "\(snapshot.id)-legacy-\(index)",
                            maximumHeight: isGraphReasoning ? nil : size.imageMaximumHeight,
                            availableWidth: isDataAnalysisComposite && cardWidth > 0
                                ? max(1, cardWidth - 28) : nil,
                            widthFraction: isDataAnalysisComposite && snapshot.imageWidthFractions.indices.contains(index)
                                ? snapshot.imageWidthFractions[index] : 1
                        )
                        Spacer(minLength: 0)
                    }
                }
                if !isDataAnalysisComposite, snapshot.imageValues.count > 3 {
                    Text("+\(snapshot.imageValues.count - 3) 张图片")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 4)
                }
            }
        }
    }

    private func tag(
        _ value: String,
        foreground: Color,
        background: Color,
        weight: Font.Weight = .regular
    ) -> some View {
        Text(value)
            .font(.system(size: 11, weight: weight))
            .foregroundStyle(foreground)
            .lineLimit(2)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func tagLine(
        label: String,
        values: [String],
        foreground: Color,
        background: Color,
        weight: Font.Weight = .regular,
        labelAlignment: VerticalAlignment = .top,
        labelTopPadding: CGFloat = 3
    ) -> some View {
        HStack(alignment: labelAlignment, spacing: 5) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, labelTopPadding)
            NativeTagFlow(spacing: 5) {
                ForEach(values, id: \.self) { value in
                    tag(value, foreground: foreground, background: background, weight: weight)
                }
            }
        }
    }

    private func sentenceTagLine(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.black)
                .fixedSize(horizontal: true, vertical: false)
                .padding(.top, 5)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(red: 143 / 255.0, green: 74 / 255.0, blue: 22 / 255.0))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 5)
                        .background(Color(red: 1, green: 242 / 255.0, blue: 229 / 255.0), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func quantityCauseTagLine(label: String, values: [String]) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 3)
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    Text(value)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func pitfallLine(value: String, label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isDataAnalysis
                    ? Color(red: 51 / 255.0, green: 51 / 255.0, blue: 51 / 255.0)
                    : Color.primary)
                .fixedSize(horizontal: true, vertical: false)
            Text(value)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(isDataAnalysis
                    ? Color(red: 51 / 255.0, green: 51 / 255.0, blue: 51 / 255.0)
                    : Color(red: 0.38, green: 0.18, blue: 0.53))
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func plainField(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 5) {
            Text("\(label)：")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.primary)
            Text(value)
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(.secondary)
                .lineLimit(size == .small ? 2 : 3)
        }
    }

    private var isLogicJudgment: Bool {
        snapshot.record.subject == "判断推理" && snapshot.record.module == "逻辑判断"
    }

    private var isAnalogyReasoning: Bool {
        snapshot.record.subject == "判断推理" && snapshot.record.module == "类比推理"
    }

    private var isGraphReasoning: Bool {
        SubjectModuleTitle.normalized(snapshot.record.subject) == "判断推理"
            && SubjectModuleTitle.normalized(snapshot.record.module) == "图形推理"
    }

    private var isDataAnalysisComposite: Bool {
        SubjectModuleTitle.normalized(snapshot.subject) == "资料分析"
            && SubjectModuleTitle.normalized(snapshot.module) == "综合题"
    }

    private var isQuantityRelations: Bool { snapshot.record.subject == "数量关系" }
    private var showsQuantityTypeInHeader: Bool { isQuantityRelations && !hidesQuantityTypeLabel }

    @ViewBuilder
    private var questionKnowledgeHeader: some View {
        let points = snapshot.knowledgePoints.joined(separator: " | ")
        if isQuantityRelations {
            VStack(alignment: .leading, spacing: 6) {
                if showsQuantityTypeInHeader {
                    knowledgeHeaderTag(quantityQuestionTypeTitle)
                }
                if !points.isEmpty {
                    knowledgePointsLine(points)
                }
            }
        } else if !points.isEmpty {
            knowledgePointsLine(points)
        }
    }

    private func knowledgePointsLine(_ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lightbulb.min")
                .font(.system(size: 11, weight: .light))
                .foregroundStyle(Color.black)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 34 / 255.0, green: 34 / 255.0, blue: 34 / 255.0))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).stroke(Color.primary.opacity(0.15), lineWidth: 0.75))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func knowledgeHeaderTag(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppTheme.accent)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(AppTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var isDataAnalysis: Bool { SubjectModuleTitle.normalized(snapshot.subject) == "资料分析" }
    private var isLogicFill: Bool {
        snapshot.record.subject == "言语理解" && snapshot.record.module == "逻辑填空"
    }

    private var displayedLogicComparisonGroups: [LogicComparisonDraft] {
        if !snapshot.comparisonWords.isEmpty {
            return snapshot.comparisonWords.map { LogicComparisonDraft(words: $0, relation: "") }
        }
        return snapshot.logicComparisonGroups
    }

    private var logicComparisonLine: some View {
        NativeTagFlow(spacing: 5) {
            ForEach(Array(displayedLogicComparisonGroups.enumerated()), id: \.offset) { _, group in
                comparisonWordGroup(group.words)
                if !group.relation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(group.relation)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparisonWordGroup(_ value: String) -> some View {
        let terms = LibraryLogicComparisonLayout.terms(in: value)
        return LibraryLogicComparisonPhraseFlow(spacing: 3) {
            ForEach(Array(terms.enumerated()), id: \.offset) { index, term in
                if index > 0 {
                    LibraryLogicComparisonSeparator()
                }
                Text(term)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppTheme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(AppTheme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
    private var quantityQuestionTypeTitle: String {
        let module = snapshot.record.module?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return module.isEmpty ? "未分类" : module
    }

    private var errorCauseLabel: String {
        if isLogicJudgment { return "选项" }
        if isAnalogyReasoning { return "二级辨析" }
        return "错因"
    }
}

private struct LibraryLogicComparisonSeparator: View {
    var body: some View {
        Rectangle().fill(AppTheme.accent.opacity(0.38))
    }
}

/// Wraps complete terms inside one comparison-group background. A divider is
/// placed only when the next term fits on the same row, so row edges stay clean.
private struct LibraryLogicComparisonPhraseFlow: Layout {
    var spacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let naturalWidth = naturalWidth(for: subviews)
        let width: CGFloat
        if let proposed = proposal.width, proposed.isFinite {
            width = max(1, min(naturalWidth, proposed))
        } else {
            width = naturalWidth
        }
        return arrange(width: width, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width.isFinite ? max(1, bounds.width) : naturalWidth(for: subviews)
        let result = arrange(width: width, subviews: subviews)
        for (index, subview) in subviews.enumerated() {
            let frame = result.frames[index]
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    private func naturalWidth(for subviews: Subviews) -> CGFloat {
        subviews.enumerated().reduce(CGFloat.zero) { partial, entry in
            let (index, subview) = entry
            let itemWidth: CGFloat
            if index.isMultiple(of: 2) {
                let width = subview.sizeThatFits(.unspecified).width
                itemWidth = width.isFinite ? max(0, width) : 0
            } else {
                itemWidth = Self.separatorWidth
            }
            return partial + itemWidth + (index == 0 ? 0 : finiteSpacing)
        }
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        var frames = Array(repeating: CGRect.zero, count: subviews.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        let safeWidth = max(1, width)

        for wordIndex in stride(from: 0, to: subviews.count, by: 2) {
            var wordSize = finite(subviews[wordIndex].sizeThatFits(.unspecified))
            if wordSize.width > safeWidth {
                wordSize = finite(subviews[wordIndex].sizeThatFits(ProposedViewSize(width: safeWidth, height: nil)))
                wordSize.width = min(safeWidth, wordSize.width)
            }

            if wordIndex > 0, x > 0 {
                let separatorIndex = wordIndex - 1
                let dividerWidth = Self.separatorWidth
                let requiredWidth = finiteSpacing + dividerWidth + finiteSpacing + wordSize.width
                if x + requiredWidth > safeWidth {
                    y += rowHeight + Self.rowSpacing
                    x = 0
                    rowHeight = 0
                } else {
                    frames[separatorIndex] = CGRect(
                        x: x + finiteSpacing,
                        y: y + max(0, (max(rowHeight, wordSize.height) - Self.separatorHeight) / 2),
                        width: dividerWidth,
                        height: Self.separatorHeight
                    )
                    x += finiteSpacing + dividerWidth + finiteSpacing
                }
            }

            frames[wordIndex] = CGRect(origin: CGPoint(x: x, y: y), size: wordSize)
            x += wordSize.width
            rowHeight = max(rowHeight, wordSize.height)
        }

        return (CGSize(width: safeWidth, height: y + rowHeight), frames)
    }

    private var finiteSpacing: CGFloat { spacing.isFinite ? max(0, spacing) : 0 }

    private func finite(_ size: CGSize) -> CGSize {
        CGSize(
            width: size.width.isFinite ? max(0, size.width) : 0,
            height: size.height.isFinite ? max(0, size.height) : 0
        )
    }

    private static let separatorWidth: CGFloat = 0.75
    private static let separatorHeight: CGFloat = 13
    private static let rowSpacing: CGFloat = 2
}

private struct LibraryCardThumbnail: View {
    let source: String
    let cacheKey: String
    let maximumHeight: CGFloat?
    let availableWidth: CGFloat?
    let widthFraction: Double
    @State private var image: UIImage?
    @State private var didFail = false
    @State private var appearanceRevision: UInt64 = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Color(uiColor: .tertiarySystemGroupedBackground)
                    .overlay {
                        if didFail {
                            Label("图片无法加载", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11, weight: .regular))
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .frame(height: min(110, maximumHeight ?? 110))
            }
        }
        .frame(width: availableWidth.map { max(1, $0 * CGFloat(widthFraction)) })
        .frame(
            maxWidth: availableWidth == nil ? .infinity : nil,
            maxHeight: maximumHeight,
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 0.7)
        }
        .task(id: "\(cacheKey)|\(appearanceRevision)") {
            didFail = false
            if let cached = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 900) {
                image = cached
                LibraryPerformanceLog.event("image.cache-hit id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
                return
            }
            let requestID = UUID()
            LibraryPerformanceLog.event("image.request id=\(LibraryPerformanceLog.shortIdentifier(cacheKey)) pixel=900")
            let loadedImage = await LibraryImageLoader.image(
                from: source,
                cacheKey: cacheKey,
                maximumPixelSize: 900,
                requestID: requestID
            )
            guard !Task.isCancelled else { return }
            image = loadedImage
            didFail = loadedImage == nil
            if loadedImage == nil {
                LibraryPerformanceLog.event("image.decode-failed id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
            }
        }
        .onChange(of: cacheKey) { _, newValue in
            image = LibraryImageLoader.cachedImage(cacheKey: newValue, maximumPixelSize: 900)
            didFail = false
        }
        .onAppear {
            appearanceRevision &+= 1
            image = LibraryImageLoader.cachedImage(cacheKey: cacheKey, maximumPixelSize: 900)
            didFail = false
            LibraryPerformanceLog.event("image.view-appear id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
        }
        .onDisappear {
            image = nil
            LibraryPerformanceLog.event("image.view-disappear id=\(LibraryPerformanceLog.shortIdentifier(cacheKey))")
        }
    }
}

enum LibraryImageLoader {
    private static let cache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 48
        cache.totalCostLimit = 80 * 1_024 * 1_024
        return cache
    }()
    fileprivate static let decodeLimiter = LibraryImageDecodeLimiter.shared
    private static let coordinator = LibraryImageLoadCoordinator.shared

    static func cachedImage(cacheKey: String, maximumPixelSize: Int) -> UIImage? {
        cache.object(forKey: cacheEntryKey(cacheKey, maximumPixelSize) as NSString)
    }

    static func image(
        from source: String,
        cacheKey: String,
        maximumPixelSize: Int,
        requestID: UUID = UUID()
    ) async -> UIImage? {
        let entryKey = cacheEntryKey(cacheKey, maximumPixelSize)
        if let cached = cache.object(forKey: entryKey as NSString) { return cached }
        return await withTaskCancellationHandler {
            await coordinator.image(
                source: source,
                imageID: cacheKey,
                entryKey: entryKey,
                maximumPixelSize: maximumPixelSize,
                requestID: requestID
            )
        } onCancel: {
            Task { await coordinator.cancel(entryKey: entryKey, requestID: requestID) }
        }
    }

    fileprivate static func cacheDecodedImage(_ image: UIImage?, entryKey: String) {
        guard let image else { return }
        let cost = max(1, Int(image.size.width * image.scale * image.size.height * image.scale * 4))
        cache.setObject(image, forKey: entryKey as NSString, cost: cost)
    }

    private static func cacheEntryKey(_ imageID: String, _ maximumPixelSize: Int) -> String {
        "\(imageID)|pixels:\(maximumPixelSize)"
    }

    fileprivate static func decode(_ source: String, maximumPixelSize: Int) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let encoded: Substring
        if let marker = source.range(of: "base64,") {
            encoded = source[marker.upperBound...]
        } else {
            encoded = source[...]
        }
        guard let data = Data(base64Encoded: String(encoded), options: .ignoreUnknownCharacters),
              !Task.isCancelled,
              let imageSource = CGImageSourceCreateWithData(data as CFData, nil),
              !Task.isCancelled else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private actor LibraryImageDecodeLimiter {
    static let shared = LibraryImageDecodeLimiter()
    private var active = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if active < 2 {
            active += 1
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        } else {
            active = max(0, active - 1)
        }
    }
}

private actor LibraryImageLoadCoordinator {
    private struct Flight {
        let id: UUID
        let task: Task<UIImage?, Never>
        var subscribers: Set<UUID>
    }

    static let shared = LibraryImageLoadCoordinator()
    private var flights: [String: Flight] = [:]

    func image(
        source: String,
        imageID: String,
        entryKey: String,
        maximumPixelSize: Int,
        requestID: UUID
    ) async -> UIImage? {
        guard !Task.isCancelled else { return nil }
        if let cached = LibraryImageLoader.cachedImage(cacheKey: imageID, maximumPixelSize: maximumPixelSize) {
            LibraryPerformanceLog.event("image.cache-hit id=\(LibraryPerformanceLog.shortIdentifier(imageID))")
            return cached
        }

        let flightID: UUID
        let task: Task<UIImage?, Never>
        if var flight = flights[entryKey] {
            flight.subscribers.insert(requestID)
            flights[entryKey] = flight
            flightID = flight.id
            task = flight.task
            LibraryPerformanceLog.event("image.join id=\(LibraryPerformanceLog.shortIdentifier(imageID))")
        } else {
            flightID = UUID()
            let limiter = LibraryImageLoader.decodeLimiter
            task = Task.detached(priority: .utility) {
                await limiter.acquire()
                guard !Task.isCancelled else {
                    await limiter.release()
                    return nil
                }
                let started = ProcessInfo.processInfo.systemUptime
                let decoded = LibraryImageLoader.decode(source, maximumPixelSize: maximumPixelSize)
                await limiter.release()
                LibraryImageLoader.cacheDecodedImage(decoded, entryKey: entryKey)
                LibraryPerformanceLog.markIfSlow(
                    "image.decode id=\(LibraryPerformanceLog.shortIdentifier(imageID)) pixels=\(maximumPixelSize)",
                    since: started,
                    thresholdMilliseconds: 24
                )
                return decoded
            }
            flights[entryKey] = Flight(id: flightID, task: task, subscribers: [requestID])
            Task { [weak self] in
                _ = await task.value
                await self?.finish(entryKey: entryKey, flightID: flightID)
            }
            LibraryPerformanceLog.event("image.decode-start id=\(LibraryPerformanceLog.shortIdentifier(imageID)) pixels=\(maximumPixelSize)")
        }
        guard !Task.isCancelled else {
            cancel(entryKey: entryKey, requestID: requestID)
            return nil
        }
        return await task.value
    }

    func cancel(entryKey: String, requestID: UUID) {
        guard var flight = flights[entryKey] else { return }
        guard flight.subscribers.remove(requestID) != nil else { return }
        if flight.subscribers.isEmpty {
            flight.task.cancel()
            flights[entryKey] = nil
            LibraryPerformanceLog.event("image.cancel id=\(LibraryPerformanceLog.shortIdentifier(entryKey))")
        } else {
            flights[entryKey] = flight
        }
    }

    private func finish(entryKey: String, flightID: UUID) {
        guard flights[entryKey]?.id == flightID else { return }
        flights[entryKey] = nil
    }
}

struct LibraryEditorImagePreview: View {
    let source: String
    let imageID: String
    var width: CGFloat? = 90
    var height: CGFloat? = 74
    var contentMode: ContentMode = .fill
    var maximumPixelSize = 600
    @State private var image: UIImage?
    @State private var appearanceRevision: UInt64 = 0

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
            } else {
                RoundedRectangle(cornerRadius: 9)
                    .fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                    .frame(height: height ?? 120)
            }
        }
        .frame(width: width, height: height, alignment: .leading)
        .frame(maxWidth: width == nil ? .infinity : nil, maxHeight: height, alignment: .leading)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .task(id: "\(imageID)|\(appearanceRevision)") {
            if let cached = LibraryImageLoader.cachedImage(cacheKey: imageID, maximumPixelSize: maximumPixelSize) {
                image = cached
                return
            }
            let loaded = await LibraryImageLoader.image(
                from: source,
                cacheKey: imageID,
                maximumPixelSize: maximumPixelSize
            )
            guard !Task.isCancelled else { return }
            image = loaded
        }
        .onChange(of: imageID) { _, newID in
            image = LibraryImageLoader.cachedImage(cacheKey: newID, maximumPixelSize: maximumPixelSize)
        }
        .onAppear {
            appearanceRevision &+= 1
            image = LibraryImageLoader.cachedImage(cacheKey: imageID, maximumPixelSize: maximumPixelSize)
        }
        .onDisappear { image = nil }
    }
}

struct LibraryMasonryGrid: View {
    let records: [LibraryRecordSnapshot]
    let kind: LibraryContentKind
    let cardSize: LibraryCardSize
    let partitionKey: String
    let onOpen: (LibraryRecordSnapshot) -> Void
    let onDelete: (LibraryRecordSnapshot) -> Void
    var hiddenTags: Set<String> = []
    var hidesQuantityTypeLabel = false
    @State private var columnAssignments: [String: Int] = [:]
    @State private var lastColumnCount: Int?
    @State private var lastPartitionKey: String?
    @State private var lastReconciledRecordIDs: [String]?
    @State private var availableWidth: CGFloat = 0
    @State private var lastAvailableWidth: CGFloat?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(0..<max(1, cardSize.columnCount), id: \.self) { columnIndex in
                LazyVStack(spacing: 12) {
                    ForEach(columns[columnIndex]) { record in
                        cardLink(record)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .top)
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: LibraryMasonryGridWidthPreferenceKey.self, value: proxy.size.width)
            }
        }
        .onPreferenceChange(LibraryMasonryGridWidthPreferenceKey.self) { width in
            guard width.isFinite, width > 0, abs(width - availableWidth) > 1 else { return }
            availableWidth = width
            reconcileColumns()
        }
        .onAppear(perform: reconcileColumns)
        .onChange(of: recordIDs) { _, _ in reconcileColumns() }
        .onChange(of: cardSize.columnCount) { _, _ in reconcileColumns() }
        .onChange(of: partitionKey) { _, _ in reconcileColumns() }
    }

    private func cardLink(_ record: LibraryRecordSnapshot) -> some View {
        Group {
            if kind == .stickies {
                LibrarySwipeDeleteCard(onDelete: { onDelete(record) }) {
                    openButton(record)
                }
            } else {
                openButton(record)
            }
        }
    }

    private func openButton(_ record: LibraryRecordSnapshot) -> some View {
        Button { onOpen(record) } label: {
            if kind == .errors {
                LibraryErrorRecordCard(
                    snapshot: record,
                    size: cardSize,
                    hidesQuantityTypeLabel: hidesQuantityTypeLabel
                )
            } else {
                LibraryRecordCard(snapshot: record, kind: kind, size: cardSize, hiddenTags: hiddenTags)
            }
        }
        .buttonStyle(LibraryCardPressStyle(animated: kind == .errors))
    }

    private var columns: [[LibraryRecordSnapshot]] {
        let count = max(1, cardSize.columnCount)
        var result = Array(repeating: [LibraryRecordSnapshot](), count: count)
        for record in records {
            let index = columnAssignments[record.id].flatMap { (0..<count).contains($0) ? $0 : nil } ?? 0
            result[index].append(record)
        }
        return result
    }

    private var recordIDs: [String] { records.map(\.id) }

    private func reconcileColumns() {
        let count = max(1, cardSize.columnCount)
        let currentIDs = recordIDs
        let widthChanged: Bool
        if let lastAvailableWidth {
            widthChanged = abs(lastAvailableWidth - availableWidth) > 1
        } else {
            widthChanged = true
        }
        if kind == .errors,
           count > 1,
           availableWidth > 0,
           lastColumnCount == count,
           lastPartitionKey == partitionKey,
           !widthChanged,
           let lastReconciledRecordIDs,
           currentIDs.count > lastReconciledRecordIDs.count,
           currentIDs.starts(with: lastReconciledRecordIDs) {
            var heights = Array(repeating: CGFloat.zero, count: count)
            var columnCardCounts = Array(repeating: 0, count: count)
            let columnWidth = max(1, (availableWidth - CGFloat(count - 1) * 12) / CGFloat(count))
            for record in records.prefix(lastReconciledRecordIDs.count) {
                guard let column = columnAssignments[record.id], heights.indices.contains(column) else { continue }
                if columnCardCounts[column] > 0 { heights[column] += 12 }
                heights[column] += estimatedHeight(of: record, availableWidth: columnWidth)
                columnCardCounts[column] += 1
            }
            for record in records.dropFirst(lastReconciledRecordIDs.count) {
                let shortestColumn = heights.indices.min { heights[$0] < heights[$1] } ?? 0
                columnAssignments[record.id] = shortestColumn
                if columnCardCounts[shortestColumn] > 0 { heights[shortestColumn] += 12 }
                heights[shortestColumn] += estimatedHeight(of: record, availableWidth: columnWidth)
                columnCardCounts[shortestColumn] += 1
            }
            self.lastReconciledRecordIDs = currentIDs
            return
        }
        guard lastColumnCount != count
                || lastPartitionKey != partitionKey
                || lastReconciledRecordIDs != currentIDs
                || widthChanged else { return }

        columnAssignments.removeAll(keepingCapacity: true)
        if kind == .errors, count > 1, availableWidth > 0 {
            var heights = Array(repeating: CGFloat.zero, count: count)
            var columnCardCounts = Array(repeating: 0, count: count)
            let columnWidth = max(1, (availableWidth - CGFloat(count - 1) * 12) / CGFloat(count))
            for record in records {
                let shortestColumn = heights.indices.min { heights[$0] < heights[$1] } ?? 0
                columnAssignments[record.id] = shortestColumn
                if columnCardCounts[shortestColumn] > 0 { heights[shortestColumn] += 12 }
                heights[shortestColumn] += estimatedHeight(of: record, availableWidth: columnWidth)
                columnCardCounts[shortestColumn] += 1
            }
        } else {
            for (index, recordID) in currentIDs.enumerated() {
                columnAssignments[recordID] = index % count
            }
        }
        lastColumnCount = count
        lastPartitionKey = partitionKey
        lastReconciledRecordIDs = currentIDs
        lastAvailableWidth = availableWidth
    }

    private func estimatedHeight(of record: LibraryRecordSnapshot, availableWidth: CGFloat) -> CGFloat {
        guard kind == .errors else { return 145 }
        let isDataAnalysisComposite = SubjectModuleTitle.normalized(record.subject) == "资料分析"
            && SubjectModuleTitle.normalized(record.module) == "综合题"
        let isDataAnalysis = SubjectModuleTitle.normalized(record.subject) == "资料分析"
        let isLogicFill = SubjectModuleTitle.normalized(record.subject) == "言语理解"
            && SubjectModuleTitle.normalized(record.module) == "逻辑填空"
        let isAnalogyReasoning = record.record.subject == "判断推理" && record.record.module == "类比推理"
        let contentWidth = max(1, availableWidth - 28)
        let titleLines = estimatedLineCount(record.title, width: contentWidth, fontSize: 14, limit: isDataAnalysisComposite ? 2 : cardSize.questionLineLimit)
        let knowledgePoints = record.knowledgePoints.joined(separator: " | ")
        let knowledgePointsWidth = max(1, contentWidth - 17) // lightbulb width plus its 6pt gap
        let knowledgePointsTextWidth = max(1, knowledgePointsWidth - 12) // shared outline padding
        let knowledgePointsHeight = knowledgePoints.isEmpty
            ? 0
            : CGFloat(estimatedLineCount(knowledgePoints, width: knowledgePointsTextWidth, fontSize: 11, limit: nil)) * 14 + 6
        var sections: [CGFloat] = []
        if record.record.subject == "数量关系" {
            var quantityHeaderHeight: CGFloat = 0
            if !hidesQuantityTypeLabel { quantityHeaderHeight += 21 }
            if !knowledgePoints.isEmpty {
                if quantityHeaderHeight > 0 { quantityHeaderHeight += 6 }
                quantityHeaderHeight += knowledgePointsHeight
            }
            if quantityHeaderHeight > 0 { sections.append(quantityHeaderHeight) }
        } else if !knowledgePoints.isEmpty {
            sections.append(knowledgePointsHeight)
        }

        if isLogicFill {
            let groups = record.comparisonWords.isEmpty
                ? record.logicComparisonGroups
                : record.comparisonWords.map { LogicComparisonDraft(words: $0, relation: "") }
            let comparisonHeight = estimatedLogicComparisonHeight(groups, width: contentWidth)
            if comparisonHeight > 0 { sections.append(comparisonHeight) }
        }

        if isDataAnalysisComposite, !record.dataAnalysisMaterialText.isEmpty {
            sections.append(CGFloat(estimatedLineCount(record.dataAnalysisMaterialText, width: contentWidth, fontSize: 11.5, limit: 2)) * 15)
        }
        if !record.imageValues.isEmpty {
            let imageCount = min(isDataAnalysisComposite ? 1 : 3, record.imageValues.count)
            sections.append(CGFloat(imageCount) * cardSize.imageMaximumHeight * 0.72 + CGFloat(max(0, imageCount - 1)) * 8)
        }
        sections.append(CGFloat(titleLines) * 19)

        if !isDataAnalysisComposite, isAnalogyReasoning, !record.options.isEmpty {
            var optionsHeight: CGFloat = CGFloat(max(0, record.options.count - 1)) * 4
            for option in record.options {
                optionsHeight += CGFloat(estimatedLineCount(option, width: contentWidth, fontSize: 13, limit: nil)) * 18
            }
            sections.append(optionsHeight)
        }

        var metadataRows: [CGFloat] = []
        if record.record.subject == "数量关系", !record.quantityStructure.isEmpty {
            metadataRows.append(estimatedFieldHeight("结构：" + record.quantityStructure, width: contentWidth, fontSize: 11))
        }
        if !record.comparisonWords.isEmpty {
            metadataRows.append(estimatedTagLineHeight(label: "辨析", values: record.comparisonWords, width: contentWidth))
        }
        if isDataAnalysis {
            let causes = LibraryDataAnalysisCauseLayout.splitLines(record.dataAnalysisErrorCause)
            if !causes.isEmpty {
                metadataRows.append(LibraryDataAnalysisCauseLayout.estimatedTagLineHeight(
                    label: "错因", values: causes, width: contentWidth
                ))
            }
        } else if record.record.collection == "errors", record.record.subject == "数量关系" {
            let causes = record.quantityErrorCauses
            if !causes.isEmpty {
                metadataRows.append(estimatedStackedTagLineHeight(
                    label: "错因", values: causes, width: contentWidth, fontSize: 10.5, verticalPadding: 6
                ))
            }
        } else if isLogicFill {
            let causes = LibraryDataAnalysisCauseLayout.splitLines(record.dataAnalysisErrorCause)
            if !causes.isEmpty {
                metadataRows.append(LibraryDataAnalysisCauseLayout.estimatedTagLineHeight(
                    label: "错因", values: causes, width: contentWidth
                ))
            }
        } else {
            if isAnalogyReasoning, !record.errorCause.isEmpty {
                metadataRows.append(estimatedFieldHeight("二级辨析：" + record.errorCause, width: contentWidth, fontSize: 11))
            } else {
                let causes = splitTags(record.errorCause)
                if !causes.isEmpty {
                    metadataRows.append(estimatedTagLineHeight(label: "错因", values: causes, width: contentWidth))
                }
            }
        }
        if !isLogicFill, !record.pitfall.isEmpty {
            metadataRows.append(estimatedFieldHeight((isDataAnalysis ? "陷阱：" : "误区：") + record.pitfall, width: contentWidth, fontSize: 11))
        }
        if !record.reminder.isEmpty {
            metadataRows.append(estimatedFieldHeight("提醒：" + record.reminder, width: contentWidth, fontSize: 11))
        }
        if !metadataRows.isEmpty {
            sections.append(metadataRows.reduce(0, +) + CGFloat(metadataRows.count - 1) * 4)
        }

        let contentHeight = sections.reduce(0, +) + CGFloat(max(0, sections.count - 1)) * 8
        return max(110, contentHeight + 28) // content plus vertical card padding
    }

    private func estimatedLogicComparisonHeight(_ groups: [LogicComparisonDraft], width: CGFloat) -> CGFloat {
        var items: [(width: CGFloat, height: CGFloat)] = []
        for group in groups {
            let words = LibraryLogicComparisonLayout.terms(in: group.words)
            if !words.isEmpty {
                items.append(estimatedLogicComparisonGroup(words, maximumWidth: width))
            }
            let relation = group.relation.trimmingCharacters(in: .whitespacesAndNewlines)
            if !relation.isEmpty {
                let size = estimatedTextSize(relation, font: UIFont.systemFont(ofSize: 10.5), width: width)
                items.append((size.width, size.height))
            }
        }
        guard !items.isEmpty else { return 0 }

        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        for item in items {
            if rowWidth > 0, rowWidth + 5 + item.width > width {
                totalHeight += rowHeight + 5
                rowWidth = 0
                rowHeight = 0
            }
            rowWidth += (rowWidth > 0 ? 5 : 0) + item.width
            rowHeight = max(rowHeight, item.height)
        }
        return totalHeight + rowHeight
    }

    private func estimatedLogicComparisonGroup(_ terms: [String], maximumWidth: CGFloat) -> (width: CGFloat, height: CGFloat) {
        let horizontalPadding: CGFloat = 12
        let verticalPadding: CGFloat = 6
        let itemSpacing: CGFloat = 3
        let font = UIFont.systemFont(ofSize: 11, weight: .medium)
        let naturalSizes = terms.map { estimatedTextSize($0, font: font, width: nil) }
        let naturalContentWidth = naturalSizes.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, terms.count - 1)) * (0.75 + itemSpacing * 2)
        let groupWidth = min(maximumWidth, naturalContentWidth + horizontalPadding)
        let contentWidth = max(1, groupWidth - horizontalPadding)

        var totalHeight: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowWidth: CGFloat = 0
        for (index, size) in naturalSizes.enumerated() {
            let wordSize = size.width > contentWidth
                ? estimatedTextSize(terms[index], font: font, width: contentWidth)
                : size
            if rowWidth > 0, rowWidth + itemSpacing + 0.75 + itemSpacing + wordSize.width > contentWidth {
                totalHeight += rowHeight + 2
                rowWidth = 0
                rowHeight = 0
            } else if rowWidth > 0 {
                rowWidth += itemSpacing + 0.75 + itemSpacing
            }
            rowWidth += wordSize.width
            rowHeight = max(rowHeight, wordSize.height)
        }
        return (groupWidth, totalHeight + rowHeight + verticalPadding)
    }

    private func estimatedTextSize(_ text: String, font: UIFont, width: CGFloat?) -> CGSize {
        let natural = (text as NSString).size(withAttributes: [.font: font])
        guard let width, width.isFinite, width > 0, natural.width > width else {
            return CGSize(width: natural.width, height: max(font.lineHeight, natural.height))
        }
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: font],
            context: nil
        )
        return CGSize(width: width, height: max(font.lineHeight, ceil(rect.height)))
    }

    private func estimatedFieldHeight(_ text: String, width: CGFloat, fontSize: CGFloat) -> CGFloat {
        CGFloat(estimatedLineCount(text, width: width, fontSize: fontSize, limit: nil)) * 15
    }

    private func estimatedTagLineHeight(label: String, values: [String], width: CGFloat) -> CGFloat {
        let labelWidth = CGFloat(label.count + 1) * 12
        let contentWidth = max(1, width - labelWidth - 5)
        var rows = 1
        var rowWidth: CGFloat = 0
        for value in values {
            let itemWidth = CGFloat(value.count) * 11 + 14
            if rowWidth > 0, rowWidth + 5 + itemWidth > contentWidth {
                rows += 1
                rowWidth = itemWidth
            } else {
                rowWidth += (rowWidth > 0 ? 5 : 0) + itemWidth
            }
        }
        return CGFloat(rows) * 19
    }

    private func estimatedStackedTagLineHeight(
        label: String,
        values: [String],
        width: CGFloat,
        fontSize: CGFloat,
        verticalPadding: CGFloat
    ) -> CGFloat {
        guard !values.isEmpty else { return 0 }
        let labelWidth = CGFloat(label.count + 1) * 12
        let textWidth = max(1, width - labelWidth - 5 - 14)
        let rows = values.reduce(CGFloat(0)) { total, value in
            let lineCount = estimatedLineCount(value, width: textWidth, fontSize: fontSize, limit: nil)
            return total + CGFloat(lineCount) * fontSize * 1.35 + verticalPadding
        }
        return rows + CGFloat(max(0, values.count - 1)) * 5
    }

    private func estimatedLineCount(_ text: String, width: CGFloat, fontSize: CGFloat, limit: Int?) -> Int {
        let charactersPerLine = max(1, Int(floor(width / fontSize)))
        let lineCount = max(1, Int(ceil(Double(text.count) / Double(charactersPerLine))))
        return limit.map { min($0, lineCount) } ?? lineCount
    }

    private func splitTags(_ value: String) -> [String] {
        value.split(whereSeparator: { "、,，".contains($0) })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private struct LibraryMasonryGridWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct LibraryCardPressStyle: ButtonStyle {
    let animated: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(animated && configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.10), value: configuration.isPressed)
            .contentShape(Rectangle())
    }
}

private struct LibrarySwipeDeleteCard<Content: View>: View {
    private let revealWidth: CGFloat = 58
    let onDelete: () -> Void
    let content: Content
    @State private var offset: CGFloat = 0

    init(onDelete: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.onDelete = onDelete
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            Button {
                withAnimation(.easeOut(duration: 0.16)) { offset = 0 }
                onDelete()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: visibleRevealWidth)
                    .frame(maxHeight: .infinity)
                    .background(visibleRevealWidth > 0 ? AppTheme.danger : .clear, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .allowsHitTesting(visibleRevealWidth > 0)

            content
                .offset(x: offset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 12)
                        .onChanged { value in
                            guard abs(value.translation.width) > abs(value.translation.height) else { return }
                            offset = min(0, max(-revealWidth, value.translation.width))
                        }
                        .onEnded { value in
                            let shouldOpen = value.predictedEndTranslation.width < -34 || value.translation.width < -30
                            withAnimation(.spring(duration: 0.22, bounce: 0.05)) { offset = shouldOpen ? -revealWidth : 0 }
                        }
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    private var visibleRevealWidth: CGFloat { min(revealWidth, max(0, -offset)) }
}
