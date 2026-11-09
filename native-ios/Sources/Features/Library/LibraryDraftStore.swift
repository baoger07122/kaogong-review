import Foundation

struct LibraryDraftSnapshot: Codable, Equatable, Sendable {
    var subject: String
    var module: String
    var reviewSource: String?
    var title: String
    var content: String
    var type: String
    var knowledgePoint: String
    var errorCause: String
    var status: String
    var options: [String]
    var optionImages: [String]?
    var optionImageIDs: [String]?
    var correctOption: String
    var userOption: String
    var pitfall: String
    var reminder: String?
    var quantityStructure: String?
    var weaknessTags: String?
    var centerComprehensionTrap: String?
    var quantityErrorCauseIsAuthoritative: Bool?
    var isDifficult: Bool?
    var needsReview: Bool?
    var questionSource: String
    var questionNumber: String?
    var accuracy: String?
    var images: [String]
    var imageDisplaySettings: [LibraryImageDisplaySetting]?
    var compareGroups: [LogicComparisonDraft]
    var score: String
    var totalScore: String
    var materials: [String]?
    var dataAnalysisMaterialText: String?
    var myAnswer: String?
    var referenceAnswer: String?
    var myAnswerIssues: String?
    var materialsAnalysis: String?
    var currentAffairsSupplement: String?
    var myFramework: String
    var standardFramework: String
    var paragraph: String
    var bias: [ShenlunBiasDraft]
    var wrongList: [String]
    var missedList: [String]
    var graphRule: String
    var recognition: String
    var pencilKitData: String
    var legacyDrawingPreview: String?
    var mindMapData: String
    var sourceExamID: String?
    var linkedErrorIDs: [String]?
    var linkedNoteIDs: [String]?
    var linkedWordIDs: [String]?
    var colorHex: String
    var pinned: Bool
    var pinyin: String?
    var sentiment: String?
    var partOfSpeech: String?
    var example: String?
    var myUnderstanding: String?
    var collocations: String?
    var wordSource: String?
    var compareNote: String?
    var commonMeaning: String?
    var wordEntryKind: String?
    var wordCompareTerms: [WordComparisonTermDraft]?

    init(_ draft: LibraryRecordDraft) {
        subject = draft.subject
        module = draft.module
        reviewSource = draft.reviewSource.rawValue
        title = draft.title
        content = draft.content
        type = draft.type
        knowledgePoint = draft.knowledgePoint
        errorCause = draft.errorCause
        status = draft.status
        options = draft.options
        optionImages = draft.optionImages
        optionImageIDs = draft.optionImageIDs
        correctOption = draft.correctOption
        userOption = draft.userOption
        pitfall = draft.pitfall
        reminder = draft.reminder
        quantityStructure = draft.quantityStructure
        weaknessTags = draft.weaknessTags
        centerComprehensionTrap = draft.centerComprehensionTrap
        quantityErrorCauseIsAuthoritative = draft.quantityErrorCauseIsAuthoritative
        isDifficult = draft.isDifficult
        needsReview = draft.needsReview
        questionSource = draft.questionSource
        questionNumber = draft.questionNumber
        accuracy = draft.accuracy
        images = draft.images
        imageDisplaySettings = LibraryImageDisplaySetting.normalized(
            draft.imageDisplaySettings,
            count: draft.images.count
        )
        compareGroups = draft.compareGroups
        score = draft.score
        totalScore = draft.totalScore
        materials = draft.materials.map(\.content)
        dataAnalysisMaterialText = draft.dataAnalysisMaterialText
        myAnswer = draft.myAnswer
        referenceAnswer = draft.referenceAnswer
        myAnswerIssues = draft.myAnswerIssues
        materialsAnalysis = draft.materialsAnalysis
        currentAffairsSupplement = draft.currentAffairsSupplement
        myFramework = draft.myFramework
        standardFramework = draft.standardFramework
        paragraph = draft.paragraph
        bias = draft.bias
        wrongList = draft.wrongList
        missedList = draft.missedList
        graphRule = draft.graphRule
        recognition = draft.recognition
        pencilKitData = draft.pencilKitData
        legacyDrawingPreview = draft.legacyDrawingPreview
        mindMapData = draft.mindMapData
        sourceExamID = draft.sourceExamID
        linkedErrorIDs = draft.linkedErrorIDs
        linkedNoteIDs = draft.linkedNoteIDs
        linkedWordIDs = draft.linkedWordIDs
        colorHex = draft.colorHex
        pinned = draft.pinned
        pinyin = draft.pinyin
        sentiment = draft.sentiment
        partOfSpeech = draft.partOfSpeech
        example = draft.example
        myUnderstanding = draft.myUnderstanding
        collocations = draft.collocations
        wordSource = draft.wordSource
        compareNote = draft.compareNote
        commonMeaning = draft.commonMeaning
        wordEntryKind = draft.wordEntryKind
        wordCompareTerms = draft.wordCompareTerms
    }

    func applying(to draft: inout LibraryRecordDraft) {
        draft.subject = subject
        draft.module = module
        if let reviewSource, let value = LibraryReviewSource(rawValue: reviewSource) { draft.reviewSource = value }
        draft.title = title
        draft.content = content
        draft.type = type
        draft.knowledgePoint = knowledgePoint
        let restoredCauseAuthority = quantityErrorCauseIsAuthoritative ?? false
        draft.quantityErrorCauseIsAuthoritative = restoredCauseAuthority
        if subject == "数量关系" {
            draft.errorCause = LibraryQuantityErrorCauseCompatibility.serialized(
                errorCause: errorCause,
                weaknessTags: weaknessTags ?? "",
                authoritative: restoredCauseAuthority
            )
        } else {
            draft.errorCause = errorCause
        }
        draft.status = status
        draft.options = options
        draft.optionImages = optionImages ?? Array(repeating: "", count: max(4, options.count))
        let storedOptionImageIDs = optionImageIDs ?? []
        draft.optionImageIDs = draft.optionImages.indices.map { index in
            let candidate = index < storedOptionImageIDs.count
                ? storedOptionImageIDs[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            return candidate.isEmpty ? UUID().uuidString : candidate
        }
        draft.correctOption = correctOption
        draft.userOption = userOption
        draft.pitfall = pitfall
        draft.reminder = reminder ?? ""
        draft.quantityStructure = quantityStructure ?? ""
        draft.weaknessTags = weaknessTags ?? ""
        draft.centerComprehensionTrap = centerComprehensionTrap ?? ""
        draft.isDifficult = isDifficult ?? false
        draft.needsReview = needsReview ?? false
        draft.questionSource = questionSource
        draft.questionNumber = questionNumber ?? ""
        draft.accuracy = accuracy ?? ""
        draft.images = images
        draft.imageDisplaySettings = LibraryImageDisplaySetting.normalized(
            imageDisplaySettings ?? [],
            count: images.count
        )
        draft.compareGroups = compareGroups
        draft.score = score
        draft.totalScore = totalScore
        let restoredMaterials = (materials ?? []).map { ShenlunMaterialDraft(content: $0) }
        draft.materials = restoredMaterials.isEmpty ? [.init()] : restoredMaterials
        draft.dataAnalysisMaterialText = dataAnalysisMaterialText ?? ""
        draft.myAnswer = myAnswer ?? ""
        draft.referenceAnswer = referenceAnswer ?? ""
        draft.myAnswerIssues = myAnswerIssues ?? ""
        draft.materialsAnalysis = materialsAnalysis ?? ""
        draft.currentAffairsSupplement = currentAffairsSupplement ?? ""
        draft.myFramework = myFramework
        draft.standardFramework = standardFramework
        draft.paragraph = paragraph
        draft.bias = bias
        draft.wrongList = wrongList
        draft.missedList = missedList
        draft.graphRule = graphRule
        draft.recognition = recognition
        draft.pencilKitData = pencilKitData
        draft.legacyDrawingPreview = legacyDrawingPreview ?? ""
        draft.mindMapData = mindMapData
        draft.sourceExamID = sourceExamID ?? ""
        draft.linkedErrorIDs = linkedErrorIDs ?? []
        draft.linkedNoteIDs = linkedNoteIDs ?? []
        draft.linkedWordIDs = linkedWordIDs ?? []
        draft.colorHex = colorHex
        draft.pinned = pinned
        draft.pinyin = pinyin ?? ""
        draft.sentiment = sentiment ?? ""
        draft.partOfSpeech = partOfSpeech ?? ""
        draft.example = example ?? ""
        draft.myUnderstanding = myUnderstanding ?? ""
        draft.collocations = collocations ?? ""
        draft.wordSource = wordSource ?? ""
        draft.compareNote = compareNote ?? ""
        draft.commonMeaning = commonMeaning ?? ""
        draft.wordEntryKind = wordEntryKind ?? WordEntryKind.word.rawValue
        draft.wordCompareTerms = wordCompareTerms ?? []
    }

    var hasUserContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
            || !(optionImages ?? []).allSatisfy(\.isEmpty)
            || !pencilKitData.isEmpty
            || !(legacyDrawingPreview ?? "").isEmpty
            || !mindMapData.isEmpty
            || !(centerComprehensionTrap ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (materials ?? []).contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            || !(dataAnalysisMaterialText ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(myAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(referenceAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(myAnswerIssues ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(materialsAnalysis ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(currentAffairsSupplement ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !questionSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !score.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !totalScore.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(pinyin ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(sentiment ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(partOfSpeech ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(example ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(myUnderstanding ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(collocations ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(wordSource ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(compareNote ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !(commonMeaning ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || (wordCompareTerms ?? []).contains {
                !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.wordID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || $0.entryKind != WordEntryKind.word.rawValue
            }
    }
}

enum LibraryDraftStore {
    static func load(kind: LibraryContentKind, scope: LibraryScope, category: String = "") -> LibraryDraftSnapshot? {
        let storageKey = key(kind: kind, scope: scope, category: category)
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let snapshot = try? JSONDecoder().decode(LibraryDraftSnapshot.self, from: data) {
            return snapshot
        }
        if scope.reviewSource == .real,
           let legacyData = UserDefaults.standard.data(forKey: legacyKey(kind: kind, scope: scope)),
           let legacySnapshot = try? JSONDecoder().decode(LibraryDraftSnapshot.self, from: legacyData) {
            return legacySnapshot
        }
        guard kind == .words, !category.isEmpty,
              let legacyData = UserDefaults.standard.data(forKey: legacyKey(kind: kind, scope: scope)),
              let legacySnapshot = try? JSONDecoder().decode(LibraryDraftSnapshot.self, from: legacyData),
              legacySnapshot.type == category else { return nil }
        UserDefaults.standard.set(legacyData, forKey: key(kind: kind, scope: scope, category: category))
        UserDefaults.standard.removeObject(forKey: legacyKey(kind: kind, scope: scope))
        return legacySnapshot
    }

    static func save(_ snapshot: LibraryDraftSnapshot, kind: LibraryContentKind, scope: LibraryScope) {
        let storageKey = key(kind: kind, scope: scope, category: snapshot.type)
        let revision = LibraryDraftRevision.next(for: storageKey)
        Task {
            await LibraryDraftPersistenceWriter.shared.enqueue(
                snapshot,
                storageKey: storageKey,
                revision: revision
            )
        }
    }

    static func clear(kind: LibraryContentKind, scope: LibraryScope, category: String = "") {
        let storageKey = key(kind: kind, scope: scope, category: category)
        let revision = LibraryDraftRevision.next(for: storageKey)
        Task {
            await LibraryDraftPersistenceWriter.shared.clear(storageKey: storageKey, revision: revision)
        }
    }

    static func flush(_ snapshot: LibraryDraftSnapshot, kind: LibraryContentKind, scope: LibraryScope) async {
        let storageKey = key(kind: kind, scope: scope, category: snapshot.type)
        let revision = LibraryDraftRevision.next(for: storageKey)
        await LibraryDraftPersistenceWriter.shared.flush(
            snapshot,
            storageKey: storageKey,
            revision: revision
        )
    }

    static func clearAndWait(kind: LibraryContentKind, scope: LibraryScope, category: String = "") async {
        let storageKey = key(kind: kind, scope: scope, category: category)
        let revision = LibraryDraftRevision.next(for: storageKey)
        await LibraryDraftPersistenceWriter.shared.clear(storageKey: storageKey, revision: revision)
    }

    private static func key(kind: LibraryContentKind, scope: LibraryScope, category: String = "") -> String {
        let subject = scope.subject ?? "all"
        let module = scope.module ?? "subject"
        let categoryKey = kind == .words ? ".category.\(category.isEmpty ? "unselected" : category)" : ""
        return "native.library.draft.\(kind.rawValue).\(scope.reviewSource.rawValue).\(subject).\(module)\(categoryKey)"
    }

    private static func legacyKey(kind: LibraryContentKind, scope: LibraryScope) -> String {
        let subject = scope.subject ?? "all"
        let module = scope.module ?? "subject"
        return "native.library.draft.\(kind.rawValue).\(subject).\(module)"
    }
}

private enum LibraryDraftRevision {
    private static let lock = NSLock()
    private static var values: [String: UInt64] = [:]

    static func next(for key: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        let next = (values[key] ?? 0) &+ 1
        values[key] = next
        return next
    }

    static func current(for key: String) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return values[key] ?? 0
    }
}

private actor LibraryDraftPersistenceWriter {
    static let shared = LibraryDraftPersistenceWriter()
    private var revisions: [String: UInt64] = [:]
    private var pendingWrites: [String: Task<Void, Never>] = [:]

    func enqueue(_ snapshot: LibraryDraftSnapshot, storageKey: String, revision: UInt64) {
        guard revision >= (revisions[storageKey] ?? 0) else { return }
        revisions[storageKey] = revision
        pendingWrites[storageKey]?.cancel()
        pendingWrites[storageKey] = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            await self?.persist(snapshot, storageKey: storageKey, revision: revision)
        }
    }

    func flush(_ snapshot: LibraryDraftSnapshot, storageKey: String, revision: UInt64) async {
        guard revision >= (revisions[storageKey] ?? 0) else { return }
        revisions[storageKey] = revision
        pendingWrites[storageKey]?.cancel()
        pendingWrites[storageKey] = nil
        await persist(snapshot, storageKey: storageKey, revision: revision)
    }

    func clear(storageKey: String, revision: UInt64) {
        guard revision >= (revisions[storageKey] ?? 0) else { return }
        revisions[storageKey] = revision
        pendingWrites[storageKey]?.cancel()
        pendingWrites[storageKey] = nil
        UserDefaults.standard.removeObject(forKey: storageKey)
    }

    private func persist(_ snapshot: LibraryDraftSnapshot, storageKey: String, revision: UInt64) async {
        guard revisions[storageKey] == revision,
              LibraryDraftRevision.current(for: storageKey) == revision else { return }
        pendingWrites[storageKey] = nil
        guard snapshot.hasUserContent else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }

        let started = ProcessInfo.processInfo.systemUptime
        let encoded = await Task.detached(priority: .utility) {
            try? JSONEncoder().encode(snapshot)
        }.value
        guard revisions[storageKey] == revision,
              LibraryDraftRevision.current(for: storageKey) == revision else { return }
        guard let encoded else {
            LibraryPerformanceLog.event("draft.write.encode-failed id=\(LibraryPerformanceLog.shortIdentifier(storageKey))")
            return
        }
        UserDefaults.standard.set(encoded, forKey: storageKey)
        LibraryPerformanceLog.markIfSlow(
            "draft.write bytes=\(encoded.count)",
            since: started,
            thresholdMilliseconds: 24
        )
    }
}
