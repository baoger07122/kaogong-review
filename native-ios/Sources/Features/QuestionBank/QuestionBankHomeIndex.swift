import Foundation

enum QuestionBankCoarseModule: String, CaseIterable, Identifiable, Sendable {
    case commonKnowledge = "常识判断"
    case language = "言语理解"
    case quantity = "数量关系"
    case reasoning = "判断推理"
    case dataAnalysis = "资料分析"
    case uncategorized = "未分类"

    var id: String { rawValue }

    static var homeOrder: [QuestionBankCoarseModule] {
        [.commonKnowledge, .language, .quantity, .reasoning, .dataAnalysis, .uncategorized]
    }

    static func classify(explicitModuleTitle title: String?) -> Self {
        switch title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" {
        case "常识判断", "常识": .commonKnowledge
        case "言语理解", "言语理解与表达": .language
        case "数量关系": .quantity
        case "判断推理": .reasoning
        case "资料分析": .dataAnalysis
        default: .uncategorized
        }
    }

    var allowedQuestionTypes: [String] {
        switch self {
        case .commonKnowledge: ["政治理论", "其他常识"]
        case .language: ["逻辑填空", "阅读与表达"]
        case .reasoning: ["图形推理", "定义判断", "类比推理", "逻辑判断"]
        case .quantity, .dataAnalysis, .uncategorized: []
        }
    }

    func questionTypeFilter(for explicitType: String) -> String {
        let normalized = explicitType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, allowedQuestionTypes.contains(normalized) else { return "未分类" }
        return normalized
    }
}

struct QuestionBankHomeFilter: Equatable, Sendable {
    var module: QuestionBankCoarseModule?
    var questionType = ""
    var year = ""
    var examType = ""
    var province = ""
    var search = ""
    var questionNumber = ""
}

struct QuestionBankHomeQuestion: Identifiable {
    let record: QuestionBankRecord
    let question: QuestionBankQuestion
    let module: QuestionBankCoarseModule
    let questionTypeFilter: String
    let moduleID: String?
    let moduleSequence: Int

    var id: String { record.compoundID }
}

struct QuestionBankHomePaper: Identifiable {
    let record: QuestionBankRecord
    let paper: QuestionBankPaper

    var id: String { record.paperID }
    var title: String { paper.title.isEmpty ? (record.title ?? "未命名试卷") : paper.title }
}

struct QuestionBankHomeIndex {
    private let papersByID: [String: QuestionBankHomePaper]
    private let recordsByPaperID: [String: [QuestionBankRecord]]
    private let questionsByPaperID: [String: [QuestionBankHomeQuestion]]
    private let orderedPapers: [QuestionBankHomePaper]

    init(records: [QuestionBankRecord]) {
        let groupedRecords = Dictionary(grouping: records, by: \.paperID)
        recordsByPaperID = groupedRecords

        var papers: [String: QuestionBankHomePaper] = [:]
        for record in records where record.kind == QuestionBankRepository.paperKind {
            guard let paper = record.decoded(QuestionBankPaper.self) else { continue }
            papers[record.paperID] = QuestionBankHomePaper(record: record, paper: paper)
        }
        papersByID = papers
        orderedPapers = papers.values.sorted { left, right in
            if left.paper.year != right.paper.year { return left.paper.year > right.paper.year }
            let titleOrder = left.title.localizedStandardCompare(right.title)
            if titleOrder == .orderedSame { return left.id < right.id }
            return titleOrder == .orderedAscending
        }

        var byPaper: [String: [QuestionBankHomeQuestion]] = [:]
        for (paperID, paperRecords) in groupedRecords {
            let modules = Dictionary(
                paperRecords
                    .filter { $0.kind == QuestionBankRepository.moduleKind }
                    .compactMap { record -> (String, QuestionBankModule)? in
                        guard let module = record.decoded(QuestionBankModule.self) else { return nil }
                        return (record.stableID, module)
                    },
                uniquingKeysWith: { first, _ in first }
            )
            byPaper[paperID] = paperRecords.compactMap { record in
                guard record.kind == QuestionBankRepository.questionKind,
                      let question = record.decoded(QuestionBankQuestion.self) else { return nil }
                let moduleID = question.moduleID.isEmpty ? record.moduleID : question.moduleID
                let module = moduleID.flatMap { modules[$0] }
                let coarse = QuestionBankCoarseModule.classify(explicitModuleTitle: module?.title)
                return QuestionBankHomeQuestion(
                    record: record,
                    question: question,
                    module: coarse,
                    questionTypeFilter: coarse.questionTypeFilter(for: question.type),
                    moduleID: moduleID,
                    moduleSequence: module?.sequence ?? Int.max
                )
            }
        }
        questionsByPaperID = byPaper
    }

    var papers: [QuestionBankHomePaper] { orderedPapers }

    var years: [String] {
        Array(Set(orderedPapers.map { String($0.paper.year) })).sorted(by: >)
    }

    var examTypes: [String] {
        Array(Set(orderedPapers.map(\.paper.examType).filter { !$0.isEmpty })).sorted()
    }

    var provinces: [String] {
        Array(Set(orderedPapers.flatMap { provinceLabels(for: $0.paper) })).sorted()
    }

    func questionTypeOptions(for module: QuestionBankCoarseModule) -> [String] {
        guard !module.allowedQuestionTypes.isEmpty else { return [] }
        let hasUnclassified = orderedPapers.contains { paper in
            (questionsByPaperID[paper.id] ?? []).contains {
                $0.module == module && $0.questionTypeFilter == "未分类"
            }
        }
        return module.allowedQuestionTypes + (hasUnclassified ? ["未分类"] : [])
    }

    func visiblePapers(matching filter: QuestionBankHomeFilter) -> [QuestionBankHomePaper] {
        orderedPapers.filter { paper in
            guard paperMatchesMetadata(paper.paper, filter: filter) else { return false }
            let searchQuery = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
            let paperMatchesSearch = !searchQuery.isEmpty && matches(paper.record.searchText, query: searchQuery)
            let questionMatches = filteredQuestions(matching: filter, paperID: paper.id).isEmpty == false
            let hasQuestionNumberFilter = Int(filter.questionNumber).map { $0 > 0 } ?? false
            let hasQuestionRestriction = filter.module != nil || !filter.questionType.isEmpty
                || hasQuestionNumberFilter
            if hasQuestionRestriction { return questionMatches }
            if searchQuery.isEmpty { return true }
            return paperMatchesSearch || questionMatches
        }
    }

    func filteredQuestions(matching filter: QuestionBankHomeFilter, paperID: String? = nil) -> [QuestionBankHomeQuestion] {
        let papersToSearch = paperID.map { [$0] } ?? orderedPapers.map(\.id)
        var result: [QuestionBankHomeQuestion] = []
        for id in papersToSearch {
            guard let paper = papersByID[id], paperMatchesMetadata(paper.paper, filter: filter) else { continue }
            let paperMatchesSearch = matches(paper.record.searchText, query: filter.search)
            for item in questionsByPaperID[id] ?? [] {
                if let module = filter.module, item.module != module { continue }
                if !filter.questionType.isEmpty, item.questionTypeFilter != filter.questionType { continue }
                if let number = Int(filter.questionNumber), number > 0, item.question.number != number { continue }
                if !paperMatchesSearch && !matches(item.record.searchText, query: filter.search) { continue }
                result.append(item)
            }
        }
        return result.sorted { left, right in
            guard left.record.paperID == right.record.paperID else {
                let leftPaper = papersByID[left.record.paperID]
                let rightPaper = papersByID[right.record.paperID]
                if leftPaper?.paper.year != rightPaper?.paper.year {
                    return (leftPaper?.paper.year ?? 0) > (rightPaper?.paper.year ?? 0)
                }
                return (leftPaper?.title ?? "").localizedStandardCompare(rightPaper?.title ?? "") == .orderedAscending
            }
            if left.moduleSequence != right.moduleSequence { return left.moduleSequence < right.moduleSequence }
            if left.question.number != right.question.number { return left.question.number < right.question.number }
            return left.id < right.id
        }
    }

    func filteredQuestionCount(for paperID: String, matching filter: QuestionBankHomeFilter) -> Int {
        filteredQuestions(matching: filter, paperID: paperID).count
    }

    func records(for paperID: String) -> [QuestionBankRecord] {
        recordsByPaperID[paperID] ?? []
    }

    private func paperMatchesMetadata(_ paper: QuestionBankPaper, filter: QuestionBankHomeFilter) -> Bool {
        if !filter.year.isEmpty, String(paper.year) != filter.year { return false }
        if !filter.examType.isEmpty, paper.examType != filter.examType { return false }
        if !filter.province.isEmpty, !provinceLabels(for: paper).contains(filter.province) { return false }
        return true
    }

    private func provinceLabels(for paper: QuestionBankPaper) -> [String] {
        let labels = [paper.provinceName, paper.provinceCode]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let sourceLabels = (paper.sourcePapers ?? []).flatMap { source in
            [source.provinceName, source.provinceCode]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        return Array(Set(labels + sourceLabels))
    }

    private func matches(_ value: String, query: String) -> Bool {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty || value.localizedCaseInsensitiveContains(normalized)
    }
}
