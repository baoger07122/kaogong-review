import Foundation

enum ShenlunWorkspaceKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case single
    case paper

    var id: String { rawValue }
    var title: String { self == .single ? "单题练习" : "套卷练习" }
}

enum ShenlunWorkspaceQuestionType: String, CaseIterable, Codable, Identifiable, Sendable {
    case single
    case document
    case essay

    var id: String { rawValue }
    var title: String {
        switch self {
        case .single: "单一题"
        case .document: "公文题"
        case .essay: "作文题"
        }
    }
}

enum ShenlunWorkspaceMaterialKind: String, Codable, Sendable {
    case text
    case pdf
    case image
}

struct ShenlunWorkspacePractice: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var kind: ShenlunWorkspaceKind
    var questionIDs: [String]
    var materialIDs: [String]
    var materialDecisionMade: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: String = UUID().uuidString,
        name: String,
        kind: ShenlunWorkspaceKind,
        questionIDs: [String] = [],
        materialIDs: [String] = [],
        materialDecisionMade: Bool = false,
        createdAt: Date = .now,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.questionIDs = questionIDs
        self.materialIDs = materialIDs
        self.materialDecisionMade = materialDecisionMade
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct ShenlunWorkspaceQuestion: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var practiceID: String
    var order: Int
    var originalNumber: String
    var type: ShenlunWorkspaceQuestionType
    var title: String
    var source: String
    var instructions: String
    var fullScore: Double?
    var minimumWordCount: Int?
    var maximumWordCount: Int?
    var materialIDs: [String]
    var materialDecisionMade: Bool?
    var referenceAnswer: String
    var revision: Int

    init(
        id: String = UUID().uuidString,
        practiceID: String,
        order: Int,
        originalNumber: String = "",
        type: ShenlunWorkspaceQuestionType = .single,
        title: String = "",
        source: String = "",
        instructions: String = "",
        fullScore: Double? = nil,
        minimumWordCount: Int? = nil,
        maximumWordCount: Int? = nil,
        materialIDs: [String] = [],
        materialDecisionMade: Bool? = nil,
        referenceAnswer: String = "",
        revision: Int = 0
    ) {
        self.id = id
        self.practiceID = practiceID
        self.order = order
        self.originalNumber = originalNumber
        self.type = type
        self.title = title
        self.source = source
        self.instructions = instructions
        self.fullScore = fullScore
        self.minimumWordCount = minimumWordCount
        self.maximumWordCount = maximumWordCount
        self.materialIDs = materialIDs
        self.materialDecisionMade = materialDecisionMade
        self.referenceAnswer = referenceAnswer
        self.revision = revision
    }
}

struct ShenlunWorkspaceLayer: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var name: String
    var isVisible: Bool

    init(id: String = UUID().uuidString, name: String, isVisible: Bool = true) {
        self.id = id
        self.name = name
        self.isVisible = isVisible
    }
}

struct ShenlunWorkspaceMaterial: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var practiceID: String
    var title: String
    var order: Int
    var kind: ShenlunWorkspaceMaterialKind
    var text: String
    var assetID: String?
    var sourceName: String?
    var selectedPDFPageIndices: [Int]
    var versionID: String
    var layers: [ShenlunWorkspaceLayer]
    var activeLayerID: String?
    var showAllLayers: Bool

    init(
        id: String = UUID().uuidString,
        practiceID: String,
        title: String,
        order: Int,
        kind: ShenlunWorkspaceMaterialKind = .text,
        text: String = "",
        assetID: String? = nil,
        sourceName: String? = nil,
        selectedPDFPageIndices: [Int] = [],
        versionID: String = UUID().uuidString,
        layers: [ShenlunWorkspaceLayer] = [.init(name: "批注")],
        activeLayerID: String? = nil,
        showAllLayers: Bool = true
    ) {
        self.id = id
        self.practiceID = practiceID
        self.title = title
        self.order = order
        self.kind = kind
        self.text = text
        self.assetID = assetID
        self.sourceName = sourceName
        self.selectedPDFPageIndices = selectedPDFPageIndices
        self.versionID = versionID
        self.layers = layers
        self.activeLayerID = activeLayerID ?? layers.first?.id
        self.showAllLayers = showAllLayers
    }
}

struct ShenlunWorkspaceAsset: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var practiceID: String
    var fileName: String
    var mimeType: String
    var data: Data
}

struct ShenlunWorkspaceDoubt: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var questionID: String
    var body: String
    var materialID: String?
    var pageIndex: Int?
    var createdAt: Date

    init(id: String = UUID().uuidString, questionID: String, body: String, materialID: String? = nil, pageIndex: Int? = nil, createdAt: Date = .now) {
        self.id = id
        self.questionID = questionID
        self.body = body
        self.materialID = materialID
        self.pageIndex = pageIndex
        self.createdAt = createdAt
    }
}

enum ShenlunWorkspaceReviewState: String, Codable, Sendable {
    case notReviewed
    case needsReview
    case pendingVerification
    case confirmed
}

struct ShenlunWorkspaceAnswer: Identifiable, Codable, Equatable, Sendable {
    var id: String { questionID }
    var practiceID: String
    var questionID: String
    var answerText: String
    var doubts: [ShenlunWorkspaceDoubt]
    var isCompleted: Bool
    var completedAt: Date?
    var revision: Int
    var reviewState: ShenlunWorkspaceReviewState
    var confirmedScore: Double?
    var confirmedAnalysis: String?

    init(
        practiceID: String,
        questionID: String,
        answerText: String = "",
        doubts: [ShenlunWorkspaceDoubt] = [],
        isCompleted: Bool = false,
        completedAt: Date? = nil,
        revision: Int = 0,
        reviewState: ShenlunWorkspaceReviewState = .notReviewed,
        confirmedScore: Double? = nil,
        confirmedAnalysis: String? = nil
    ) {
        self.practiceID = practiceID
        self.questionID = questionID
        self.answerText = answerText
        self.doubts = doubts
        self.isCompleted = isCompleted
        self.completedAt = completedAt
        self.revision = revision
        self.reviewState = reviewState
        self.confirmedScore = confirmedScore
        self.confirmedAnalysis = confirmedAnalysis
    }
}

struct ShenlunWorkspaceDrawing: Identifiable, Codable, Equatable, Sendable {
    var id: String
    var practiceID: String
    var materialID: String
    var materialVersionID: String
    var pageID: String
    var layerID: String
    var drawingData: Data
    var updatedAt: Date
}

enum ShenlunWorkspaceRoute: Hashable {
    case practice(id: String, selectedQuestionID: String?)
    case editor(practiceID: String?, questionID: String?, kind: ShenlunWorkspaceKind)
    case legacy(recordID: String)
    case legacyAdaptation(recordID: String)
}
