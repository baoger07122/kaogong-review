import SwiftUI

enum RootTab: String, CaseIterable, Identifiable {
    case home
    case library
    case review
    case exams
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "首页"
        case .library: "学习库"
        case .review: "复习"
        case .exams: "套卷"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .library: "books.vertical"
        case .review: "clock.arrow.circlepath"
        case .exams: "doc.text"
        case .settings: "gearshape"
        }
    }
}

enum AppTheme {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
}
