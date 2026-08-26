import Foundation

enum AppRoute: Hashable {
    case studyStats
    case speedPractice
    case subject(String)
    case module(subject: String, module: String)
    case errorDetail(String)
    case noteDetail(String)
    case examDetail(String)
}

