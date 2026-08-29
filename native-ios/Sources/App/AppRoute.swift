import Foundation

enum AppRoute: Hashable {
    case todoStats
    case studyReport
    case speedPractice
    case currentAffairs
    case knowledgePoints
    case subject(String)
    case module(subject: String, module: String)
    case errorDetail(String)
    case noteDetail(String)
    case examDetail(String)
}
