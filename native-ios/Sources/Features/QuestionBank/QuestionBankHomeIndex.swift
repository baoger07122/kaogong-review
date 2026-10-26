import Foundation

enum QuestionBankModuleTitle {
    static func normalized(_ title: String?) -> String {
        var value = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        for pattern in [
            "^[一二三四五六七八九十百]+[、.．)）]\\s*",
            "^[0-9]+[、.．)）]\\s*",
            "^[（(][一二三四五六七八九十百]+[）)]\\s*"
        ] {
            value = value.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

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
        switch QuestionBankModuleTitle.normalized(title) {
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
    var difficultOnly = false
    var needsReviewOnly = false
    var knowledgePoint = ""
    var weaknessTag = ""

    var hasQuestionRestriction: Bool {
        module != nil || !questionType.isEmpty
            || (Int(questionNumber).map { $0 > 0 } ?? false)
            || difficultOnly || needsReviewOnly
            || !knowledgePoint.isEmpty || !weaknessTag.isEmpty
    }
}

struct QuestionBankHomeQuestion: Identifiable {
    let record: QuestionBankRecord
    let question: QuestionBankQuestion
    let module: QuestionBankCoarseModule
    let questionTypeFilter: String
    let moduleID: String?
    let moduleTitle: String?
    let moduleSequence: Int

    var id: String { record.compoundID }
}

struct QuestionBankHomeIndexRevision: Hashable, Sendable {
    let compoundID: String
    let paperID: String
    let kind: String
    let stableID: String
    let moduleID: String?
    let questionNumber: Int?
    let sequence: Int?
    let year: Int?
    let title: String?
    let contentRevision: Int
    let assetRelativePath: String?

    init(record: QuestionBankRecord) {
        compoundID = record.compoundID
        paperID = record.paperID
        kind = record.kind
        stableID = record.stableID
        moduleID = record.moduleID
        questionNumber = record.questionNumber
        sequence = record.sequence
        year = record.year
        title = record.title
        contentRevision = record.contentRevision
        assetRelativePath = record.assetRelativePath
    }

    static func make(records: [QuestionBankRecord]) -> [QuestionBankHomeIndexRevision] {
        records.map { QuestionBankHomeIndexRevision(record: $0) }
            .sorted { $0.compoundID < $1.compoundID }
    }
}

struct QuestionBankHomeIndexInput: Sendable {
    let revision: QuestionBankHomeIndexRevision
    let payload: Data
    let searchText: String

    init(record: QuestionBankRecord) {
        revision = QuestionBankHomeIndexRevision(record: record)
        payload = record.payload
        searchText = record.searchText
    }
}

struct QuestionBankHomeIndexSnapshot: Sendable {
    struct Paper: Sendable {
        let compoundID: String
        let paperID: String
        let title: String?
        let searchText: String
        let value: QuestionBankPaper
    }

    struct Question: Sendable {
        let compoundID: String
        let paperID: String
        let value: QuestionBankQuestion
        let moduleTitle: String?
        let moduleSequence: Int
    }

    let revision: [QuestionBankHomeIndexRevision]
    let papers: [Paper]
    let questionsByPaperID: [String: [Question]]
    let materialsByPaperID: [String: [QuestionBankMaterial]]

    static func build(records: [QuestionBankHomeIndexInput]) -> QuestionBankHomeIndexSnapshot {
        let decoder = JSONDecoder()
        let groupedRecords = Dictionary(grouping: records, by: { $0.revision.paperID })
        var papers: [Paper] = []
        var questionsByPaperID: [String: [Question]] = [:]
        var materialsByPaperID: [String: [QuestionBankMaterial]] = [:]

        for (paperID, paperRecords) in groupedRecords {
            var modules: [String: QuestionBankModule] = [:]
            for input in paperRecords where input.revision.kind == QuestionBankRepository.moduleKind {
                guard let module = try? decoder.decode(QuestionBankModule.self, from: input.payload) else { continue }
                modules[input.revision.stableID] = module
            }

            for input in paperRecords {
                switch input.revision.kind {
                case QuestionBankRepository.paperKind:
                    guard let value = try? decoder.decode(QuestionBankPaper.self, from: input.payload) else { continue }
                    papers.append(Paper(
                        compoundID: input.revision.compoundID,
                        paperID: paperID,
                        title: input.revision.title,
                        searchText: input.searchText,
                        value: value
                    ))
                case QuestionBankRepository.questionKind:
                    guard let value = try? decoder.decode(QuestionBankQuestion.self, from: input.payload) else { continue }
                    let moduleID = value.moduleID.isEmpty ? input.revision.moduleID : value.moduleID
                    let module = moduleID.flatMap { modules[$0] }
                    questionsByPaperID[paperID, default: []].append(Question(
                        compoundID: input.revision.compoundID,
                        paperID: paperID,
                        value: value,
                        moduleTitle: module?.title,
                        moduleSequence: module?.sequence ?? Int.max
                    ))
                case QuestionBankRepository.materialKind:
                    guard let value = try? decoder.decode(QuestionBankMaterial.self, from: input.payload) else { continue }
                    materialsByPaperID[paperID, default: []].append(value)
                default:
                    continue
                }
            }
        }

        return QuestionBankHomeIndexSnapshot(
            revision: records.map(\.revision).sorted { $0.compoundID < $1.compoundID },
            papers: papers,
            questionsByPaperID: questionsByPaperID,
            materialsByPaperID: materialsByPaperID
        )
    }
}

struct QuestionBankHomeFilterResult {
    let visiblePapers: [QuestionBankHomePaper]
    let questionsByPaperID: [String: [QuestionBankHomeQuestion]]

    func questionCount(for paperID: String) -> Int {
        questionsByPaperID[paperID]?.count ?? 0
    }
}

struct QuestionBankHomePaper: Identifiable {
    let record: QuestionBankRecord
    let paper: QuestionBankPaper

    var id: String { record.paperID }
    var title: String { paper.title.isEmpty ? (record.title ?? "未命名试卷") : paper.title }
}

struct QuestionBankOverviewCandidate: Identifiable, Equatable {
    let id: String
    let paperID: String
    let paperTitle: String
    let questionNumber: Int
    let moduleID: String
    let moduleTitle: String
    let moduleSequence: Int
    let type: String
    let subject: String
}

struct QuestionBankOverviewGroup: Identifiable, Equatable {
    let id: String
    let paperID: String
    let paperTitle: String
    let moduleID: String
    let moduleTitle: String
    let coarseQuestionType: String?
    let startsModule: Bool
    let questions: [QuestionBankOverviewCandidate]
}

enum QuestionBankOverviewGrouping {
    private struct GroupKey: Hashable {
        let paperID: String
        let moduleID: String
        let coarseQuestionType: String?
    }

    static func groups(from candidates: [QuestionBankOverviewCandidate]) -> [QuestionBankOverviewGroup] {
        // `candidates` already follows the reader's canonical ordered question IDs.
        // Sorting again here can send an overview jump to a different visible order.
        let ordered = candidates

        var groupKeys: [GroupKey] = []
        var groupQuestions: [[QuestionBankOverviewCandidate]] = []
        for candidate in ordered {
            let type = coarseType(for: candidate)
            let key = GroupKey(
                paperID: candidate.paperID,
                moduleID: candidate.moduleID,
                coarseQuestionType: type
            )
            if groupKeys.last == key {
                groupQuestions[groupQuestions.count - 1].append(candidate)
            } else {
                groupKeys.append(key)
                groupQuestions.append([candidate])
            }
        }

        return groupKeys.enumerated().compactMap { groupIndex, key in
            guard let first = groupQuestions[groupIndex].first else { return nil }
            let identity = Data(
                "\(key.paperID)\u{0}\(key.moduleID)\u{0}\(key.coarseQuestionType ?? "")\u{0}\(groupIndex)".utf8
            ).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            return QuestionBankOverviewGroup(
                id: identity,
                paperID: first.paperID,
                paperTitle: first.paperTitle,
                moduleID: first.moduleID,
                moduleTitle: first.moduleTitle.isEmpty ? "未分类" : first.moduleTitle,
                coarseQuestionType: key.coarseQuestionType,
                startsModule: groupIndex == 0
                    || groupKeys[groupIndex - 1].paperID != key.paperID
                    || groupKeys[groupIndex - 1].moduleID != key.moduleID,
                questions: groupQuestions[groupIndex]
            )
        }
    }

    private static func coarseType(for candidate: QuestionBankOverviewCandidate) -> String? {
        let module = QuestionBankCoarseModule.classify(explicitModuleTitle: candidate.moduleTitle)
        let label = candidate.type.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? candidate.subject.trimmingCharacters(in: .whitespacesAndNewlines)
            : candidate.type.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = QuestionBankModuleTitle.normalized(label)

        switch module {
        case .language:
            if ["逻辑填空", "选词填空", "词语填空"].contains(where: { normalized.contains($0) }) {
                return "逻辑填空"
            }
            let readingKinds = ["阅读", "主旨", "意图", "细节", "标题", "语句排序", "语句衔接", "下文推断", "词句理解"]
            if readingKinds.contains(where: { normalized.contains($0) }) { return "片段阅读" }
            return "未分类"
        case .reasoning:
            let types = ["图形推理", "定义判断", "类比推理", "逻辑判断"]
            return types.first(where: { normalized == $0 || normalized.contains($0) }) ?? "未分类"
        case .commonKnowledge:
            if normalized.contains("政治理论") { return "政治理论" }
            if ["常识", "常识判断", "其他常识"].contains(normalized) { return "常识" }
            return "未分类"
        case .quantity, .dataAnalysis:
            return nil
        case .uncategorized:
            return "未分类"
        }
    }

}

struct QuestionBankHomeIndex {
    private let papersByID: [String: QuestionBankHomePaper]
    private let recordsByPaperID: [String: [QuestionBankRecord]]
    private let questionsByPaperID: [String: [QuestionBankHomeQuestion]]
    private let materialsByPaperID: [String: [QuestionBankMaterial]]
    private let orderedPapers: [QuestionBankHomePaper]
    let revision: [QuestionBankHomeIndexRevision]

    init(records: [QuestionBankRecord]) {
        self.init(
            snapshot: .build(records: records.map { QuestionBankHomeIndexInput(record: $0) }),
            records: records
        )
    }

    init(snapshot: QuestionBankHomeIndexSnapshot, records: [QuestionBankRecord]) {
        let recordsByID = Dictionary(records.map { ($0.compoundID, $0) }, uniquingKeysWith: { first, _ in first })
        let groupedRecords = Dictionary(grouping: records, by: \.paperID)
        revision = snapshot.revision
        recordsByPaperID = groupedRecords

        var papers: [String: QuestionBankHomePaper] = [:]
        for indexed in snapshot.papers {
            guard let record = recordsByID[indexed.compoundID] else { continue }
            papers[indexed.paperID] = QuestionBankHomePaper(record: record, paper: indexed.value)
        }
        papersByID = papers
        orderedPapers = papers.values.sorted { left, right in
            if left.paper.year != right.paper.year { return left.paper.year > right.paper.year }
            let titleOrder = left.title.localizedStandardCompare(right.title)
            if titleOrder == .orderedSame { return left.id < right.id }
            return titleOrder == .orderedAscending
        }

        var byPaper: [String: [QuestionBankHomeQuestion]] = [:]
        for (paperID, indexedQuestions) in snapshot.questionsByPaperID {
            byPaper[paperID] = indexedQuestions.compactMap { indexed in
                guard let record = recordsByID[indexed.compoundID] else { return nil }
                let moduleID = indexed.value.moduleID.isEmpty ? record.moduleID : indexed.value.moduleID
                let coarse = QuestionBankCoarseModule.classify(explicitModuleTitle: indexed.moduleTitle)
                return QuestionBankHomeQuestion(
                    record: record,
                    question: indexed.value,
                    module: coarse,
                    questionTypeFilter: coarse.questionTypeFilter(for: indexed.value.type),
                    moduleID: moduleID,
                    moduleTitle: indexed.moduleTitle,
                    moduleSequence: indexed.moduleSequence
                )
            }
        }
        questionsByPaperID = byPaper
        materialsByPaperID = snapshot.materialsByPaperID
    }

    static func defaultPaperIDs(records: [QuestionBankRecord]) -> [String] {
        records.filter { $0.kind == QuestionBankRepository.paperKind }.sorted { left, right in
            if left.year != right.year { return (left.year ?? 0) > (right.year ?? 0) }
            let titleOrder = (left.title ?? "未命名试卷").localizedStandardCompare(right.title ?? "未命名试卷")
            if titleOrder == .orderedSame { return left.paperID < right.paperID }
            return titleOrder == .orderedAscending
        }.map(\.paperID)
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

    var knowledgePoints: [String] {
        Array(Set(allQuestions.flatMap { $0.question.knowledgePoints ?? [] })).sorted()
    }

    var weaknessTags: [String] {
        Array(Set(allQuestions.flatMap { $0.question.weaknessTags ?? [] })).sorted()
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
        filtered(matching: filter).visiblePapers
    }

    func filtered(matching filter: QuestionBankHomeFilter) -> QuestionBankHomeFilterResult {
        let questions = filteredQuestions(matching: filter)
        let grouped = Dictionary(grouping: questions, by: { $0.record.paperID })
        let searchQuery = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let papers = orderedPapers.filter { paper in
            guard paperMatchesMetadata(paper.paper, filter: filter) else { return false }
            let paperMatchesSearch = !searchQuery.isEmpty && matches(paper.record.searchText, query: searchQuery)
            let questionMatches = !(grouped[paper.id] ?? []).isEmpty
            if filter.hasQuestionRestriction { return questionMatches }
            if searchQuery.isEmpty { return true }
            return paperMatchesSearch || questionMatches
        }
        return QuestionBankHomeFilterResult(visiblePapers: papers, questionsByPaperID: grouped)
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
                if filter.difficultOnly, item.question.isDifficult != true { continue }
                if filter.needsReviewOnly, item.question.needsReview != true { continue }
                if !filter.knowledgePoint.isEmpty,
                   !(item.question.knowledgePoints ?? []).contains(filter.knowledgePoint) { continue }
                if !filter.weaknessTag.isEmpty,
                   !(item.question.weaknessTags ?? []).contains(filter.weaknessTag) { continue }
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

    func materials(for paperID: String) -> [QuestionBankMaterial] {
        materialsByPaperID[paperID] ?? []
    }

    private var allQuestions: [QuestionBankHomeQuestion] {
        questionsByPaperID.values.flatMap { $0 }
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
