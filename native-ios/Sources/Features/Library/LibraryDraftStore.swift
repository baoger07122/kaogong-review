import Foundation

struct LibraryDraftSnapshot: Codable, Equatable {
    var subject: String
    var module: String
    var title: String
    var content: String
    var type: String
    var knowledgePoint: String
    var errorCause: String
    var status: String
    var options: [String]
    var correctOption: String
    var userOption: String
    var pitfall: String
    var questionSource: String
    var images: [String]
    var compareGroups: [LogicComparisonDraft]
    var score: String
    var totalScore: String
    var myFramework: String
    var standardFramework: String
    var paragraph: String
    var bias: [ShenlunBiasDraft]
    var wrongList: [String]
    var missedList: [String]
    var graphRule: String
    var recognition: String
    var pencilKitData: String
    var mindMapData: String
    var colorHex: String
    var pinned: Bool

    init(_ draft: LibraryRecordDraft) {
        subject = draft.subject
        module = draft.module
        title = draft.title
        content = draft.content
        type = draft.type
        knowledgePoint = draft.knowledgePoint
        errorCause = draft.errorCause
        status = draft.status
        options = draft.options
        correctOption = draft.correctOption
        userOption = draft.userOption
        pitfall = draft.pitfall
        questionSource = draft.questionSource
        images = draft.images
        compareGroups = draft.compareGroups
        score = draft.score
        totalScore = draft.totalScore
        myFramework = draft.myFramework
        standardFramework = draft.standardFramework
        paragraph = draft.paragraph
        bias = draft.bias
        wrongList = draft.wrongList
        missedList = draft.missedList
        graphRule = draft.graphRule
        recognition = draft.recognition
        pencilKitData = draft.pencilKitData
        mindMapData = draft.mindMapData
        colorHex = draft.colorHex
        pinned = draft.pinned
    }

    func applying(to draft: inout LibraryRecordDraft) {
        draft.subject = subject
        draft.module = module
        draft.title = title
        draft.content = content
        draft.type = type
        draft.knowledgePoint = knowledgePoint
        draft.errorCause = errorCause
        draft.status = status
        draft.options = options
        draft.correctOption = correctOption
        draft.userOption = userOption
        draft.pitfall = pitfall
        draft.questionSource = questionSource
        draft.images = images
        draft.compareGroups = compareGroups
        draft.score = score
        draft.totalScore = totalScore
        draft.myFramework = myFramework
        draft.standardFramework = standardFramework
        draft.paragraph = paragraph
        draft.bias = bias
        draft.wrongList = wrongList
        draft.missedList = missedList
        draft.graphRule = graphRule
        draft.recognition = recognition
        draft.pencilKitData = pencilKitData
        draft.mindMapData = mindMapData
        draft.colorHex = colorHex
        draft.pinned = pinned
    }

    var hasUserContent: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !images.isEmpty
            || !pencilKitData.isEmpty
            || !mindMapData.isEmpty
    }
}

enum LibraryDraftStore {
    static func load(kind: LibraryContentKind, scope: LibraryScope) -> LibraryDraftSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: key(kind: kind, scope: scope)) else { return nil }
        return try? JSONDecoder().decode(LibraryDraftSnapshot.self, from: data)
    }

    static func save(_ snapshot: LibraryDraftSnapshot, kind: LibraryContentKind, scope: LibraryScope) {
        let storageKey = key(kind: kind, scope: scope)
        guard snapshot.hasUserContent, let data = try? JSONEncoder().encode(snapshot) else {
            UserDefaults.standard.removeObject(forKey: storageKey)
            return
        }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear(kind: LibraryContentKind, scope: LibraryScope) {
        UserDefaults.standard.removeObject(forKey: key(kind: kind, scope: scope))
    }

    private static func key(kind: LibraryContentKind, scope: LibraryScope) -> String {
        let subject = scope.subject ?? "all"
        let module = scope.module ?? "subject"
        return "native.library.draft.\(kind.rawValue).\(subject).\(module)"
    }
}
