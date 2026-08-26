import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let cardRadius: CGFloat = 18
    static let contentSpacing: CGFloat = 16
}

struct NativeCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(18)
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

extension View {
    func nativeCard() -> some View { modifier(NativeCardModifier()) }
}

struct NativeSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.title2.bold())
            Spacer()
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}

