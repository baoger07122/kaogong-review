import SwiftUI

enum AppTheme {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let success = Color(red: 0.14, green: 0.55, blue: 0.58)
    static let warning = Color(red: 1.0, green: 0.58, blue: 0.0)
    static let danger = Color(red: 1.0, green: 0.23, blue: 0.19)
    static let report = Color(red: 0.58, green: 0.42, blue: 0.95)

    static let groupedBackground = Color(uiColor: .systemGroupedBackground)
    static let secondaryBackground = Color(uiColor: .secondarySystemGroupedBackground)

    static let controlRadius: CGFloat = 13
    static let cardRadius: CGFloat = 18
    static let modalRadius: CGFloat = 22
    static let contentSpacing: CGFloat = 16
    static let cardPadding: CGFloat = 17

    static let pageTitleFont = Font.system(size: 22, weight: .semibold)
    static let sectionTitleFont = Font.system(size: 16, weight: .semibold)
    static let cardTitleFont = Font.system(size: 14, weight: .medium)
    static let bodyFont = Font.system(size: 13, weight: .regular)
    static let inputFont = Font.system(size: 13, weight: .regular)
    static let fieldLabelFont = Font.system(size: 11, weight: .medium)
    static let auxiliaryFont = Font.system(size: 11, weight: .regular)
    static let actionFont = Font.system(size: 13, weight: .semibold)
}

struct NativeCardModifier: ViewModifier {
    var padding: CGFloat = AppTheme.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }
}

extension View {
    func nativeCard(padding: CGFloat = AppTheme.cardPadding) -> some View {
        modifier(NativeCardModifier(padding: padding))
    }
}

struct NativePageTitle: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(AppTheme.pageTitleFont)
            if let subtitle {
                Text(subtitle)
                    .font(AppTheme.auxiliaryFont)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct NativeSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(AppTheme.sectionTitleFont)
            Spacer()
            if let subtitle {
                Text(subtitle).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
            }
        }
    }
}
