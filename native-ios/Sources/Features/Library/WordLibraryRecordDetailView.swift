import SwiftUI
import SwiftData

struct WordLibraryRecordDetailView: View {
    let record: StoredRecord
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil
    var onOpenLinkedError: ((String) -> Void)? = nil

    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "errors" }) private var errorRecords: [StoredRecord]
    @Query(filter: #Predicate<StoredRecord> { $0.collection == "words" }) private var wordRecords: [StoredRecord]
    @State private var showDelete = false
    @State private var showErrorSelection = false
    @State private var operationErrorTitle = "关联错题失败"
    @State private var reviewErrorMessage: String?
    @State private var linkedWordDetailTarget: LinkedWordDetailTarget?

    private var object: [String: Any] { record.jsonObject ?? [:] }
    private var category: WordCategory {
        WordCategory(rawValue: text("category", "type")) ?? .idiomDefinition
    }
    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 7) {
                        detailTag(category.title, color: AppTheme.accent)
                    }

                    Text(displayTitle)
                        .font(.system(size: 22, weight: .semibold))
                        .textSelection(.enabled)

                    Text("内容")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                    NativeRichTextDisplay(
                        html: LibraryComparisonDocumentProjection.wordContent(in: object, category: category),
                        minHeight: 34,
                        tableAppearance: .libraryContent
                    )
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)

                    linkedErrorSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 28)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color.white)

            if showDelete, let onDelete {
                NativeDeleteDialog(
                    title: "删除词语记录",
                    message: "删除后将同时解除与错题的关联。",
                    onDelete: { showDelete = false; onDelete() },
                    onCancel: { showDelete = false }
                )
            }
        }
        .navigationTitle("词语详情")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $linkedWordDetailTarget) { target in
            if let linked = wordRecords.first(where: { $0.recordID == target.recordID }) {
                WordLibraryRecordDetailView(record: linked, onOpenLinkedError: onOpenLinkedError)
            }
        }
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if onEdit != nil || onDelete != nil {
                    Menu {
                        if let onEdit {
                            Button(action: onEdit) {
                                Label("编辑词语", systemImage: "pencil")
                            }
                        }
                        if onDelete != nil {
                            Button(role: .destructive) { showDelete = true } label: {
                                Label("删除词语", systemImage: "trash")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .accessibilityLabel("词语设置")
                }
            }
            .documentToolbarBackground()
        }
        .alert(operationErrorTitle, isPresented: Binding(
            get: { reviewErrorMessage != nil },
            set: { if !$0 { reviewErrorMessage = nil } }
        )) {
            Button("好", role: .cancel) { reviewErrorMessage = nil }
        } message: {
            Text(reviewErrorMessage ?? "")
        }
        .sheet(isPresented: $showErrorSelection) {
            LibraryRelationSelectionDialog(
                collection: "errors",
                candidates: errorRecords,
                selection: linkedErrorSelection,
                onClose: { showErrorSelection = false }
            )
        }
    }

    @ViewBuilder
    private var linkedErrorSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label("关联错题", systemImage: "link")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("编辑") { showErrorSelection = true }
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.plain)
                    .foregroundStyle(AppTheme.accent)
            }

            if linkedErrorRecords.isEmpty {
                Text("还没有关联错题")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(linkedErrorRecords, id: \.compoundID) { error in
                    linkedErrorRow(error)
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func linkedErrorRow(_ error: StoredRecord) -> some View {
        let snapshot = LibraryRecordSnapshot(record: error)
        let row = VStack(alignment: .leading, spacing: 4) {
            Text(errorReferenceLine(snapshot))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
            Text(snapshot.title)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .contentShape(Rectangle())

        if let onOpenLinkedError {
            Button { onOpenLinkedError(error.recordID) } label: { row }
                .buttonStyle(.plain)
        } else {
            NavigationLink(value: AppRoute.errorDetail(error.recordID)) { row }
                .buttonStyle(.plain)
        }
    }

    private func errorReferenceLine(_ snapshot: LibraryRecordSnapshot) -> String {
        let source = snapshot.questionSource.trimmingCharacters(in: .whitespacesAndNewlines)
        let number = snapshot.questionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        let sourceText = source.isEmpty ? "来源未填写" : source
        let numberText: String
        if number.isEmpty {
            numberText = "题号未填写"
        } else if number.hasPrefix("第") || number.hasSuffix("题") {
            numberText = number
        } else {
            numberText = "第\(number)题"
        }
        return "\(sourceText) · \(numberText)"
    }

    private var linkedErrorIDs: [String] {
        let object = record.compatibilityIndexObject ?? [:]
        let reverseIDs = errorRecords.compactMap { error -> String? in
            let wordIDs = error.compatibilityIndexObject?["linkedWordIds"] as? [String] ?? []
            return wordIDs.contains(record.recordID) ? error.recordID : nil
        }
        return LibraryWordErrorAssociationPolicy.resolvedErrorIDs(
            linkedErrors: object["linkedErrors"] as? [String],
            relatedErrorIDs: object["relatedErrorIds"] as? [String],
            reverseLinkedErrorIDs: reverseIDs,
            existingErrorIDs: Set(errorRecords.map(\.recordID))
        )
    }

    private var linkedErrorRecords: [StoredRecord] {
        let errorsByID = Dictionary(uniqueKeysWithValues: errorRecords.map { ($0.recordID, $0) })
        return linkedErrorIDs.compactMap { errorsByID[$0] }
    }

    private var linkedErrorSelection: Binding<[String]> {
        Binding(
            get: { linkedErrorIDs },
            set: { newIDs in
                operationErrorTitle = "关联错题失败"
                do {
                    try LibraryRecordRepository.updateLinkedErrors(
                        word: record,
                        newIDs: newIDs,
                        errorRecords: errorRecords,
                        context: modelContext
                    )
                } catch {
                    reviewErrorMessage = error.localizedDescription
                }
            }
        )
    }

    private var wordComparisonDetail: some View {
        VStack(alignment: .leading, spacing: 16) {
            detailText("共同语义", value: text("commonMeaning"))
            if compareTerms.contains(where: { !$0.coreFocus.isEmpty || !$0.quickDecision.isEmpty }) {
                wordComparisonTable
            }
            let terms = compareTerms.filter { !$0.name.isEmpty || !$0.meaning.isEmpty }
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("逐词释义").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                    ForEach(Array(terms.enumerated()), id: \.offset) { index, term in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(term.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                            if !term.meaning.isEmpty {
                                NativeRichTextDisplay(html: term.meaning, minHeight: 24)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                        if index < terms.count - 1 {
                            Rectangle().fill(Color.primary.opacity(0.10)).frame(height: 0.7)
                        }
                    }
                }
            }
            comparisonTakeaway
            detailText("拼音", value: text("pinyin"))
            detailText("词性", value: text("pos", "partOfSpeech"))
            detailText("例句", value: text("example"))
            detailText("我的理解", value: text("myUnderstanding"))
            detailText("常见搭配", value: text("collocations"))
            detailText("来源", value: text("source"))
        }
    }

    private var idiomComparisonDetail: some View {
        let terms = compareTerms
        let context = text("idiomComparisonContext")
        let contextTerms = terms.filter { !$0.contextExample.isEmpty || !$0.contextFocus.isEmpty }
        let judgmentTerms = terms.filter { !$0.quickDecision.isEmpty }
        return VStack(alignment: .leading, spacing: 16) {
            if !terms.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    WordComparisonTableRow(columnFractions: [0.22, 0.52, 0.26]) {
                        tableCell("成语", header: true)
                        tableCell("词义", header: true)
                        tableCell("核心侧重", header: true)
                    }
                    ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                        WordComparisonTableRow(columnFractions: [0.22, 0.52, 0.26]) {
                            linkedTermButton(term)
                            if term.meaning.isEmpty {
                                tableCell("")
                            } else {
                                NativeRichTextDisplay(html: term.meaning, minHeight: 18)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 9)
                                    .overlay(alignment: .bottom) {
                                        Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.65)
                                    }
                            }
                            tableCell(term.coreFocus, emphasized: true)
                        }
                    }
                }
            }
            if !context.isEmpty || !contextTerms.isEmpty {
                idiomContextExamples(title: context.isEmpty ? "同一情境" : "同一情境｜\(context)", terms: contextTerms)
            }
            if !judgmentTerms.isEmpty {
                idiomComparisonExamples(title: "一眼判断", terms: judgmentTerms, value: \.quickDecision)
            }
        }
    }

    private func idiomComparisonExamples(title: String, terms: [Term], value: KeyPath<Term, String>) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    linkedTermButton(term)
                    Text(term[keyPath: value]).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
                }
            }
        }
    }

    private func idiomContextExamples(title: String, terms: [Term]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            ForEach(Array(terms.enumerated()), id: \.offset) { _, term in
                VStack(alignment: .leading, spacing: 4) {
                    linkedTermButton(term)
                    if !term.contextExample.isEmpty { Text(term.contextExample).font(.system(size: 13)).lineSpacing(3) }
                    if !term.contextFocus.isEmpty {
                        Text("情境侧重：\(term.contextFocus)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private func linkedTermButton(_ term: Term) -> some View {
        if !term.wordID.isEmpty, wordRecords.contains(where: { $0.recordID == term.wordID }) {
            Button {
                linkedWordDetailTarget = LinkedWordDetailTarget(recordID: term.wordID)
            } label: {
                HStack(spacing: 4) {
                    Text(term.name).font(.system(size: 14, weight: .semibold))
                    Image(systemName: "link").font(.system(size: 10, weight: .medium))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppTheme.accent)
        } else {
            Text(term.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
        }
    }

    private var wordComparisonTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("一眼对照")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.bottom, 6)
            WordComparisonTableRow {
                tableCell("词语", header: true)
                tableCell("核心侧重", header: true)
                tableCell("一眼判断", header: true)
            }
            ForEach(Array(compareTerms.enumerated()), id: \.offset) { _, term in
                if !term.coreFocus.isEmpty || !term.quickDecision.isEmpty {
                    WordComparisonTableRow {
                        tableCell(term.name)
                        tableCell(term.coreFocus)
                        tableCell(term.quickDecision)
                    }
                }
            }
        }
        .background(Color.white)
    }

    private func tableCell(_ value: String, header: Bool = false, emphasized: Bool = false) -> some View {
        Text(value.isEmpty ? "—" : value)
            .font(.system(size: header ? 12 : 14, weight: emphasized ? .semibold : (header ? .medium : .regular)))
            .foregroundStyle(header ? Color.secondary : Color.primary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, header ? 8 : 9)
            .background(Color.white)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.12)).frame(height: 0.65) }
    }

    @ViewBuilder private var comparisonTakeaway: some View {
        let core = text("compareNote", "coreDifference")
        let hint = text("judgmentHint")
        if !core.isEmpty && !hint.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    detailText("核心区别", value: core)
                    richTextSection("判断提示", html: hint)
                }
                VStack(alignment: .leading, spacing: 12) {
                    detailText("核心区别", value: core)
                    richTextSection("判断提示", html: hint)
                }
            }
        } else if !core.isEmpty {
            detailText("核心区别", value: core)
        } else {
            richTextSection("判断提示", html: hint)
        }
    }

    @ViewBuilder private func richTextSection(_ label: String, html: String) -> some View {
        if !html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 7) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                NativeRichTextDisplay(html: html, minHeight: 30)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder private func detailText(_ label: String, value: String) -> some View {
        if !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                Text(value).font(.system(size: 14)).lineSpacing(4).textSelection(.enabled)
            }
        }
    }

    private func detailTag(_ value: String, color: Color) -> some View {
        Text(value)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .frame(height: 25)
            .background(color.opacity(0.09), in: Capsule())
    }

    private var recordTitle: String {
        let value = text("name", "words", "title")
        return value.isEmpty ? "未命名词语" : value
    }

    private var displayTitle: String {
        recordTitle
    }

    private struct Term {
        let name: String
        let meaning: String
        let coreFocus: String
        let quickDecision: String
        let contextExample: String
        let contextFocus: String
        let wordID: String
    }

    private var compareTerms: [Term] {
        guard let values = object["compareWords"] as? [[String: Any]] else { return [] }
        return values.compactMap { value in
            let name = value["name"] as? String ?? ""
            guard !name.isEmpty else { return nil }
            return Term(
                name: name,
                meaning: value["meaning"] as? String ?? "",
                coreFocus: value["coreFocus"] as? String ?? value["focus"] as? String ?? "",
                quickDecision: value["quickDecision"] as? String ?? value["decision"] as? String ?? "",
                contextExample: value["contextExample"] as? String ?? "",
                contextFocus: value["contextFocus"] as? String ?? "",
                wordID: value["wordId"] as? String ?? value["id"] as? String ?? ""
            )
        }
    }

    private func text(_ keys: String...) -> String {
        for key in keys {
            if let value = object[key] as? String, !value.isEmpty { return value }
        }
        return ""
    }
}

private struct WordComparisonTableRow: Layout {
    var columnFractions: [CGFloat] = [0.17, 0.28, 0.55]

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width?.isFinite == true ? max(1, proposal.width!) : 360
        let columnWidths = columnFractions.map { width * $0 }
        let heights = subviews.enumerated().map { index, view in
            view.sizeThatFits(ProposedViewSize(width: columnWidths[min(index, 2)], height: nil)).height
        }
        return CGSize(width: width, height: heights.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnFractions.map { bounds.width * $0 }
        var x = bounds.minX
        for (index, view) in subviews.enumerated() {
            let width = widths[min(index, 2)]
            view.place(at: CGPoint(x: x, y: bounds.minY), proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width
        }
    }
}
