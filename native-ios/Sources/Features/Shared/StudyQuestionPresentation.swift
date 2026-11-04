import SwiftUI

enum SubjectModuleTitle {
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

enum StudyOptionMarkerState: Equatable {
    case unselected
    case selected
    case selectedFilled
    case correct
    case incorrect
}

enum StudyOptionRowLayout {
    static func verticalAlignment(hasText: Bool) -> VerticalAlignment {
        hasText ? .firstTextBaseline : .top
    }
}

enum StudyOptionFeedbackPalette {
    static let correct = Color(red: 52.0 / 255.0, green: 199.0 / 255.0, blue: 89.0 / 255.0)
    static let incorrect = AppTheme.danger
    static let correctBackground = correct.opacity(0.10)
    static let incorrectBackground = incorrect.opacity(0.09)
}

struct StudyOptionMarker: View {
    let letter: String
    let state: StudyOptionMarkerState
    var diameter: CGFloat = 26
    var font: Font = .system(size: 16, weight: .regular)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(letter)
            .font(font.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .frame(width: diameter, height: diameter)
            .background(fillColor, in: Circle())
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: state)
            .overlay {
                if state == .unselected || state == .selected {
                    Circle().stroke(outlineColor, lineWidth: state == .selected ? 1.5 : 1)
                }
            }
    }

    private var foregroundColor: Color {
        switch state {
        case .unselected: .primary
        case .selected: AppTheme.accent
        case .selectedFilled: .white
        case .correct, .incorrect: .white
        }
    }

    private var fillColor: Color {
        switch state {
        case .unselected, .selected: .clear
        case .selectedFilled: AppTheme.accent
        case .correct: StudyOptionFeedbackPalette.correct
        case .incorrect: StudyOptionFeedbackPalette.incorrect
        }
    }

    private var outlineColor: Color {
        switch state {
        case .unselected: Color(uiColor: .separator).opacity(0.8)
        case .selected, .selectedFilled: AppTheme.accent
        case .correct: StudyOptionFeedbackPalette.correct
        case .incorrect: StudyOptionFeedbackPalette.incorrect
        }
    }
}
