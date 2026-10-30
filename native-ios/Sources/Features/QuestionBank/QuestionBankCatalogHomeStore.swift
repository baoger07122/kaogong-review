import Foundation
import SwiftData
import SwiftUI

struct QuestionBankCatalogHomeFilterResult: Sendable {
    let visiblePapers: [QuestionBankCatalogPaperSummary]
    let matchingQuestionsByPaperID: [String: [QuestionBankCatalogQuestionSummary]]
    let questionCountsByPaperID: [String: Int]

    var totalQuestionCount: Int {
        questionCountsByPaperID.values.reduce(0, +)
    }

    func questionCount(for paperID: String) -> Int {
        questionCountsByPaperID[paperID] ?? 0
    }
}

struct QuestionBankCatalogHomeFilterRequestID: Hashable, Sendable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let filter: QuestionBankHomeFilter
    /// Nil while the text-search result for this filter is still being prepared.
    let searchResultVersion: Int?
}

struct QuestionBankCatalogHomeRequestGeneration {
    private(set) var current = 0

    mutating func begin() -> Int {
        current &+= 1
        return current
    }

    func accepts(_ generation: Int) -> Bool {
        generation == current
    }
}

private struct QuestionBankCatalogSearchCacheKey: Hashable {
    let catalogVersion: QuestionBankCatalogDataVersion
    let query: String
}

private struct QuestionBankCatalogCachedSearch {
    let matches: QuestionBankCatalogSearchMatches
    let resultVersion: Int
}

private struct QuestionBankCatalogHomeFilterCacheKey: Hashable {
    let requestID: QuestionBankCatalogHomeFilterRequestID
}

extension QuestionBankCatalogHomeSnapshot {
    var years: [String] { filterOptions.years }
    var examTypes: [String] { filterOptions.examTypes }
    var provinces: [String] { filterOptions.provinces }
    var knowledgePoints: [String] { filterOptions.knowledgePoints }
    var weaknessTags: [String] { filterOptions.weaknessTags }

    func containsPaper(year: Int) -> Bool {
        filterOptions.knownYears.contains(year)
    }

    func questionTypeOptions(for module: QuestionBankCoarseModule) -> [String] {
        filterOptions.questionTypeOptionsByModule[module.rawValue] ?? []
    }

    func questionRoute(paperID: String, questionNumber: Int) -> QuestionBankCatalogQuestionRoute? {
        let key = QuestionBankCatalogQuestionRouteKey(paperID: paperID, questionNumber: questionNumber)
        return filterOptions.questionRoutes[key]
    }

    func filtered(
        matching filter: QuestionBankHomeFilter,
        questions: [QuestionBankCatalogQuestionSummary],
        searchMatches: QuestionBankCatalogSearchMatches? = nil
    ) throws -> QuestionBankCatalogHomeFilterResult {
        let normalized = filter.normalizedForCatalog
        let query = normalized.search
        let isQuestionNumberSearch = Int(normalized.questionNumber).map { $0 > 0 } ?? false
        let hasTextSearch = !query.isEmpty && !isQuestionNumberSearch
        var metadataPapers: [QuestionBankCatalogPaperSummary] = []
        metadataPapers.reserveCapacity(papers.count)
        for (index, paper) in papers.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            if paperMatchesMetadata(paper, filter: normalized) {
                metadataPapers.append(paper)
            }
        }

        // The default and paper-metadata-only path uses precomputed paper counts.
        // It intentionally does not group, traverse, or sort question summaries.
        if !normalized.hasQuestionRestriction && !hasTextSearch {
            var paperQuestionCounts: [String: Int] = [:]
            paperQuestionCounts.reserveCapacity(metadataPapers.count)
            for (index, paper) in metadataPapers.enumerated() {
                if index.isMultiple(of: 128) { try Task.checkCancellation() }
                paperQuestionCounts[paper.paperID] = paper.questionCount
            }
            return QuestionBankCatalogHomeFilterResult(
                visiblePapers: metadataPapers,
                matchingQuestionsByPaperID: [:],
                questionCountsByPaperID: paperQuestionCounts
            )
        }

        let hasCurrentSearchVersion = searchMatches?.catalogVersion == Optional(catalogVersion)
        let validSearchMatches = hasTextSearch && hasCurrentSearchVersion ? searchMatches : nil
        let paperSearchHits = validSearchMatches?.paperIDs ?? Set<String>()
        let questionSearchHits = validSearchMatches?.questionCompoundIDs ?? Set<String>()
        let metadataPaperIDs = Set(metadataPapers.map(\.paperID))
        let papersByID = Dictionary(papers.map { ($0.paperID, $0) }, uniquingKeysWith: { first, _ in first })
        var groupedMatches: [String: [QuestionBankCatalogQuestionSummary]] = [:]

        for (index, question) in questions.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard metadataPaperIDs.contains(question.paperID) else { continue }
            if let module = normalized.module, question.coarseModule != module.rawValue { continue }
            if !normalized.questionType.isEmpty, question.coarseQuestionType != normalized.questionType { continue }
            if let number = Int(normalized.questionNumber).flatMap({ $0 > 0 ? $0 : nil }),
               question.originalNumber != number { continue }
            if normalized.difficultOnly && !question.isDifficult { continue }
            if normalized.needsReviewOnly && !question.needsReview { continue }
            if !normalized.knowledgePoint.isEmpty,
               !question.knowledgePoints.contains(normalized.knowledgePoint) { continue }
            if !normalized.weaknessTag.isEmpty,
               !question.weaknessTags.contains(normalized.weaknessTag) { continue }

            if hasTextSearch {
                let paperMatchedSearch = paperSearchHits.contains(question.paperID)
                if !paperMatchedSearch && !questionSearchHits.contains(question.sourceCompoundID) {
                    continue
                }
                if !normalized.hasQuestionRestriction && paperMatchedSearch {
                    // A paper-title hit represents the whole paper. The card count
                    // comes from the paper summary, so no question rows are needed.
                    continue
                }
            }
            groupedMatches[question.paperID, default: []].append(question)
        }

        for key in Array(groupedMatches.keys) {
            try Task.checkCancellation()
            groupedMatches[key]?.sort { left, right in
                let leftPaper = papersByID[left.paperID]
                let rightPaper = papersByID[right.paperID]
                if leftPaper?.year != rightPaper?.year {
                    return (leftPaper?.year ?? 0) > (rightPaper?.year ?? 0)
                }
                let titleOrder = (leftPaper?.title ?? "").localizedStandardCompare(rightPaper?.title ?? "")
                if titleOrder != .orderedSame { return titleOrder == .orderedAscending }
                if left.paperID != right.paperID { return left.paperID < right.paperID }
                if left.moduleSequence != right.moduleSequence { return left.moduleSequence < right.moduleSequence }
                if left.questionTypeSequence != right.questionTypeSequence {
                    return left.questionTypeSequence < right.questionTypeSequence
                }
                if left.originalNumber != right.originalNumber { return left.originalNumber < right.originalNumber }
                return left.sourceCompoundID < right.sourceCompoundID
            }
        }

        var visible: [QuestionBankCatalogPaperSummary] = []
        var counts: [String: Int] = [:]
        for (index, paper) in metadataPapers.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            let matches = groupedMatches[paper.paperID] ?? []
            if normalized.hasQuestionRestriction {
                guard !matches.isEmpty else { continue }
                counts[paper.paperID] = matches.count
            } else if hasTextSearch {
                let paperMatchedSearch = paperSearchHits.contains(paper.paperID)
                guard paperMatchedSearch || !matches.isEmpty else { continue }
                counts[paper.paperID] = paperMatchedSearch ? paper.questionCount : matches.count
            } else {
                counts[paper.paperID] = paper.questionCount
            }
            visible.append(paper)
        }
        return QuestionBankCatalogHomeFilterResult(
            visiblePapers: visible,
            matchingQuestionsByPaperID: groupedMatches,
            questionCountsByPaperID: counts
        )
    }

    private func paperMatchesMetadata(
        _ paper: QuestionBankCatalogPaperSummary,
        filter: QuestionBankHomeFilter
    ) -> Bool {
        if !filter.year.isEmpty, String(paper.year) != filter.year { return false }
        if !filter.examType.isEmpty, paper.examType != filter.examType { return false }
        if !filter.province.isEmpty, !paper.provinceLabels.contains(filter.province) { return false }
        return true
    }
}

private extension QuestionBankHomeFilter {
    var normalizedForCatalog: QuestionBankHomeFilter {
        var value = self
        value.search = search.trimmingCharacters(in: .whitespacesAndNewlines)
        value.questionNumber = questionNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        return value
    }
}

@MainActor
final class QuestionBankCatalogHomeStore: ObservableObject {
    @Published private(set) var snapshot: QuestionBankCatalogHomeSnapshot?
    @Published private(set) var status: QuestionBankCatalogStatus?
    @Published private(set) var isLoading = false
    @Published private(set) var isSearching = false
    @Published private(set) var isPreparingFilter = false
    @Published private(set) var searchQuery: String?
    @Published private(set) var errorMessage: String?
    @Published private(set) var requestGeneration = 0
    @Published private(set) var loadedGeneration: Int?
    @Published private(set) var filterPreparationRevision = 0

    // Read by behavior tests to verify repeated body lookups do not recompute.
    private(set) var filterComputationCount = 0

    private var activeLoadID: UUID?
    private var activeSearchID: UUID?
    private var filterGeneration = QuestionBankCatalogHomeRequestGeneration()
    private var questionRefreshGeneration = QuestionBankCatalogHomeRequestGeneration()
    private var activeFilterTask: Task<QuestionBankCatalogHomeFilterResult, Error>?
    private var activeQuestionRefreshTask: Task<QuestionBankCatalogHomeSnapshot, Error>?
    private var searchResultSequence = 0
    private var searchCache: [QuestionBankCatalogSearchCacheKey: QuestionBankCatalogCachedSearch] = [:]
    private var filterCache: [QuestionBankCatalogHomeFilterCacheKey: QuestionBankCatalogHomeFilterResult] = [:]
    private var questionFilterCache: [QuestionBankCatalogDataVersion: [QuestionBankCatalogQuestionSummary]] = [:]
    private var searchQuestionCache: [QuestionBankCatalogSearchCacheKey: [QuestionBankCatalogQuestionSummary]] = [:]

    var isCurrent: Bool {
        snapshot != nil && status?.state == .ready && loadedGeneration == requestGeneration
    }

    func containsPaper(year: Int) -> Bool {
        snapshot?.containsPaper(year: year) == true
    }

    func filterRequestID(for filter: QuestionBankHomeFilter) -> QuestionBankCatalogHomeFilterRequestID? {
        guard isCurrent, let snapshot else { return nil }
        let normalized = filter.normalizedForCatalog
        let isQuestionNumberSearch = Int(normalized.questionNumber).map { $0 > 0 } ?? false
        let hasTextSearch = !normalized.search.isEmpty && !isQuestionNumberSearch
        let resultVersion: Int?
        if hasTextSearch {
            let searchKey = QuestionBankCatalogSearchCacheKey(
                catalogVersion: snapshot.catalogVersion,
                query: normalized.search
            )
            resultVersion = searchCache[searchKey]?.resultVersion
        } else {
            resultVersion = 0
        }
        return QuestionBankCatalogHomeFilterRequestID(
            catalogVersion: snapshot.catalogVersion,
            filter: normalized,
            searchResultVersion: resultVersion
        )
    }

    /// A body lookup is a bounded dictionary lookup; all filtering happens in
    /// `prepareFilter` on a detached worker and is keyed by data/filter/search versions.
    func filtered(matching filter: QuestionBankHomeFilter) -> QuestionBankCatalogHomeFilterResult? {
        guard let requestID = filterRequestID(for: filter),
              let key = filterCacheKey(for: requestID) else { return nil }
        return filterCache[key]
    }

    func prepareFilter(matching filter: QuestionBankHomeFilter, in container: ModelContainer) async {
        guard let snapshot,
              let requestID = filterRequestID(for: filter),
              let key = filterCacheKey(for: requestID) else {
            cancelFilterPreparation()
            return
        }
        if filterCache[key] != nil {
            if activeFilterTask != nil {
                cancelFilterTaskOnly()
                _ = filterGeneration.begin()
            }
            isPreparingFilter = false
            return
        }
        let searchMatches = searchMatches(for: requestID)
        if !requestID.filter.search.isEmpty,
           Int(requestID.filter.questionNumber).map({ $0 > 0 }) == nil,
           searchMatches == nil {
            isPreparingFilter = false
            return
        }

        cancelFilterTaskOnly()
        let requestGeneration = filterGeneration.begin()
        isPreparingFilter = true
        do {
            let questions = try await questionSummaries(
                for: requestID,
                searchMatches: searchMatches,
                container: container
            )
            guard filterGeneration.accepts(requestGeneration),
                  self.snapshot?.catalogVersion == requestID.catalogVersion,
                  filterRequestID(for: filter) == requestID,
                  isCurrent else { return }
            let worker = Task.detached(priority: .userInitiated) {
                try snapshot.filtered(
                    matching: requestID.filter,
                    questions: questions,
                    searchMatches: searchMatches
                )
            }
            activeFilterTask = worker
            filterComputationCount += 1
            let result = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard filterGeneration.accepts(requestGeneration),
                  self.snapshot?.catalogVersion == requestID.catalogVersion,
                  filterRequestID(for: filter) == requestID,
                  isCurrent else { return }
            filterCache[key] = result
            if filterCache.count > 32, let firstKey = filterCache.keys.first {
                filterCache.removeValue(forKey: firstKey)
            }
            activeFilterTask = nil
            isPreparingFilter = false
            filterPreparationRevision &+= 1
        } catch {
            guard filterGeneration.accepts(requestGeneration) else { return }
            activeFilterTask = nil
            isPreparingFilter = false
        }
    }

    func requestReload() {
        activeLoadID = nil
        activeSearchID = nil
        cancelQuestionRefresh()
        cancelFilterPreparation()
        requestGeneration &+= 1
        isLoading = false
        isSearching = false
        searchCache.removeAll(keepingCapacity: true)
        filterCache.removeAll(keepingCapacity: true)
        questionFilterCache.removeAll(keepingCapacity: true)
        searchQuestionCache.removeAll(keepingCapacity: true)
    }

    func cancelLoad() {
        activeLoadID = nil
        activeSearchID = nil
        cancelQuestionRefresh()
        cancelFilterPreparation()
        isLoading = false
        isSearching = false
    }

    func load(in container: ModelContainer, generation: Int) async {
        guard generation == requestGeneration else { return }
        let loadID = UUID()
        activeLoadID = loadID
        errorMessage = nil
        isLoading = true
        do {
            let initialStatus = try await QuestionBankCatalogService.status(in: container)
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            status = initialStatus

            if initialStatus.state != .ready {
                let result = try await QuestionBankCatalogService.buildOrResume(in: container) { [weak self] update in
                    Task { @MainActor in
                        guard self?.activeLoadID == loadID else { return }
                        self?.status = update
                    }
                }
                guard activeLoadID == loadID, !Task.isCancelled else { return }
                status = result.status
            }

            let loaded = try await QuestionBankCatalogService.homeSnapshot(in: container)
            guard activeLoadID == loadID, !Task.isCancelled else { return }
            snapshot = loaded
            status = loaded.status
            loadedGeneration = generation
            searchCache.removeAll(keepingCapacity: true)
            filterCache.removeAll(keepingCapacity: true)
            questionFilterCache.removeAll(keepingCapacity: true)
            searchQuestionCache.removeAll(keepingCapacity: true)
        } catch is CancellationError {
            status = try? await QuestionBankCatalogService.status(in: container)
        } catch {
            guard activeLoadID == loadID else { return }
            errorMessage = error.localizedDescription
            status = try? await QuestionBankCatalogService.status(in: container)
        }
        if activeLoadID == loadID {
            activeLoadID = nil
            isLoading = false
        }
    }

    func beginSearch(_ query: String) {
        activeSearchID = UUID()
        searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        isSearching = !(searchQuery ?? "").isEmpty
        if !isSearching { activeSearchID = nil }
        if !query.isEmpty { errorMessage = nil }
    }

    /// Applies a contiguous single-question catalog update by refreshing the
    /// prepared directory snapshot. Version gaps or missing identities ask the
    /// caller for a full reload.
    func refreshQuestions(
        for changes: [QuestionBankRecordChangeSignal.RecordChange],
        in container: ModelContainer
    ) async -> Bool {
        let contentChanges = changes.filter { $0.kind == .questionContent }
        guard !contentChanges.isEmpty, isCurrent, let oldSnapshot = snapshot else { return false }
        cancelQuestionRefresh()
        let refreshGeneration = questionRefreshGeneration.begin()
        let uniqueKeys = Set(contentChanges.map { "\($0.paperID)|\($0.recordID)" })
        let expectedVersion = oldSnapshot.catalogVersion
        let worker = Task.detached(priority: .userInitiated) {
            let batch = try await QuestionBankCatalogService.questionSummaries(for: contentChanges, in: container)
            guard batch.catalogVersion.generationID == expectedVersion.generationID,
                  batch.catalogVersion.revision == expectedVersion.revision + uniqueKeys.count else {
                throw CancellationError()
            }
            let returnedKeys = Set(batch.questions.map { "\($0.paperID)|\($0.questionID)" })
            guard uniqueKeys.isSubset(of: returnedKeys) else {
                throw QuestionBankCatalogServiceFailure.notReady(.needsRepair)
            }
            let refreshedSnapshot = try await QuestionBankCatalogService.homeSnapshot(in: container)
            guard refreshedSnapshot.catalogVersion == batch.catalogVersion else {
                throw CancellationError()
            }
            return refreshedSnapshot
        }
        activeQuestionRefreshTask = worker
        do {
            let refreshedSnapshot = try await withTaskCancellationHandler {
                try await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard questionRefreshGeneration.accepts(refreshGeneration),
                  isCurrent,
                  snapshot?.catalogVersion == expectedVersion else {
                if questionRefreshGeneration.accepts(refreshGeneration) {
                    activeQuestionRefreshTask = nil
                }
                return false
            }
            activeQuestionRefreshTask = nil
            cancelFilterPreparation()
            activeSearchID = nil
            isSearching = false
            snapshot = refreshedSnapshot
            status = refreshedSnapshot.status
            searchCache.removeAll(keepingCapacity: true)
            filterCache.removeAll(keepingCapacity: true)
            questionFilterCache.removeAll(keepingCapacity: true)
            searchQuestionCache.removeAll(keepingCapacity: true)
            filterPreparationRevision &+= 1
            return true
        } catch {
            if questionRefreshGeneration.accepts(refreshGeneration) {
                activeQuestionRefreshTask = nil
            }
            return false
        }
    }

    func search(_ query: String, in container: ModelContainer) async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            searchQuery = nil
            isSearching = false
            activeSearchID = nil
            return
        }
        guard let snapshot else { return }
        let key = QuestionBankCatalogSearchCacheKey(catalogVersion: snapshot.catalogVersion, query: normalized)
        if searchCache[key] != nil {
            searchQuery = normalized
            isSearching = false
            errorMessage = nil
            return
        }
        let requestID = activeSearchID ?? UUID()
        activeSearchID = requestID
        searchQuery = normalized
        isSearching = true
        errorMessage = nil
        do {
            let matches = try await QuestionBankCatalogService.searchMatches(query: normalized, in: container)
            guard activeSearchID == requestID, !Task.isCancelled else { return }
            guard let matchVersion = matches.catalogVersion,
                  matchVersion == snapshot.catalogVersion,
                  self.snapshot?.catalogVersion == snapshot.catalogVersion else {
                isSearching = false
                requestReload()
                return
            }
            searchResultSequence &+= 1
            searchCache[key] = QuestionBankCatalogCachedSearch(
                matches: matches,
                resultVersion: searchResultSequence
            )
            if searchCache.count > 16,
               let staleKey = searchCache.keys.first(where: { $0 != key }) {
                searchCache.removeValue(forKey: staleKey)
            }
            isSearching = false
        } catch is CancellationError {
            if activeSearchID == requestID { isSearching = false }
        } catch {
            if activeSearchID == requestID {
                errorMessage = error.localizedDescription
                isSearching = false
            }
        }
    }

    private func filterCacheKey(
        for requestID: QuestionBankCatalogHomeFilterRequestID
    ) -> QuestionBankCatalogHomeFilterCacheKey? {
        let normalized = requestID.filter
        let isQuestionNumberSearch = Int(normalized.questionNumber).map { $0 > 0 } ?? false
        if !normalized.search.isEmpty, !isQuestionNumberSearch, requestID.searchResultVersion == nil {
            return nil
        }
        return QuestionBankCatalogHomeFilterCacheKey(requestID: requestID)
    }

    private func questionSummaries(
        for requestID: QuestionBankCatalogHomeFilterRequestID,
        searchMatches: QuestionBankCatalogSearchMatches?,
        container: ModelContainer
    ) async throws -> [QuestionBankCatalogQuestionSummary] {
        if requestID.filter.hasQuestionRestriction {
            if let cached = questionFilterCache[requestID.catalogVersion] { return cached }
            let batch = try await QuestionBankCatalogService.questionSummaries(
                forSourceCompoundIDs: nil,
                in: container
            )
            guard batch.catalogVersion == requestID.catalogVersion,
                  self.snapshot?.catalogVersion == requestID.catalogVersion else {
                requestReload()
                throw CancellationError()
            }
            questionFilterCache[requestID.catalogVersion] = batch.questions
            return batch.questions
        }

        let query = requestID.filter.search
        let isQuestionNumberSearch = Int(requestID.filter.questionNumber).map { $0 > 0 } ?? false
        guard !query.isEmpty, !isQuestionNumberSearch,
              let searchMatches,
              !searchMatches.questionCompoundIDs.isEmpty else { return [] }
        let key = QuestionBankCatalogSearchCacheKey(catalogVersion: requestID.catalogVersion, query: query)
        if let cached = searchQuestionCache[key] { return cached }
        let batch = try await QuestionBankCatalogService.questionSummaries(
            forSourceCompoundIDs: searchMatches.questionCompoundIDs,
            in: container
        )
        guard batch.catalogVersion == requestID.catalogVersion,
              self.snapshot?.catalogVersion == requestID.catalogVersion else {
            requestReload()
            throw CancellationError()
        }
        searchQuestionCache[key] = batch.questions
        if searchQuestionCache.count > 16, let firstKey = searchQuestionCache.keys.first {
            searchQuestionCache.removeValue(forKey: firstKey)
        }
        return batch.questions
    }

    private func searchMatches(
        for requestID: QuestionBankCatalogHomeFilterRequestID
    ) -> QuestionBankCatalogSearchMatches? {
        let query = requestID.filter.search
        guard !query.isEmpty,
              Int(requestID.filter.questionNumber).map({ $0 > 0 }) == nil,
              let cached = searchCache[QuestionBankCatalogSearchCacheKey(
                catalogVersion: requestID.catalogVersion,
                query: query
              )],
              let resultVersion = requestID.searchResultVersion,
              cached.resultVersion == resultVersion else { return nil }
        return cached.matches
    }

    private func cancelFilterPreparation() {
        cancelFilterTaskOnly()
        _ = filterGeneration.begin()
        isPreparingFilter = false
    }

    private func cancelQuestionRefresh() {
        activeQuestionRefreshTask?.cancel()
        activeQuestionRefreshTask = nil
        _ = questionRefreshGeneration.begin()
    }

    private func cancelFilterTaskOnly() {
        activeFilterTask?.cancel()
        activeFilterTask = nil
    }
}
