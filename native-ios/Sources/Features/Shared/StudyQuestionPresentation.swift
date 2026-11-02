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
    case correct
    case incorrect
}

enum StudyOptionRowLayout {
    static func verticalAlignment(hasText: Bool) -> VerticalAlignment {
        hasText ? .firstTextBaseline : .top
    }
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
        case .correct, .incorrect: .white
        }
    }

    private var fillColor: Color {
        switch state {
        case .unselected, .selected: .clear
        case .correct: AppTheme.success
        case .incorrect: AppTheme.danger
        }
    }

    private var outlineColor: Color {
        switch state {
        case .unselected: Color(uiColor: .separator).opacity(0.8)
        case .selected: AppTheme.accent
        case .correct: AppTheme.success
        case .incorrect: AppTheme.danger
        }
    }
}
