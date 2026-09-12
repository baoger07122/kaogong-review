import SwiftUI

struct NativeDesignSystemView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                standardSection("字体") {
                    fontSample("页面标题", detail: "22 pt · Semibold", font: AppTheme.pageTitleFont)
                    fontSample("分区标题", detail: "16 pt · Semibold", font: AppTheme.sectionTitleFont)
                    fontSample("卡片标题", detail: "15 pt · Medium", font: AppTheme.cardTitleFont)
                    fontSample("正文与输入", detail: "14 pt · Regular", font: AppTheme.bodyFont)
                    fontSample("笔记正文", detail: "16 pt · Regular", font: AppTheme.noteBodyFont)
                    fontSample("字段与辅助信息", detail: "12 pt", font: AppTheme.auxiliaryFont)
                }

                standardSection("语义颜色") {
                    HStack(spacing: 10) {
                        colorSample("主操作", AppTheme.accent)
                        colorSample("完成", AppTheme.success)
                        colorSample("提醒", AppTheme.warning)
                        colorSample("危险", AppTheme.danger)
                    }
                }

                standardSection("基础组件") {
                    HStack(spacing: 10) {
                        Button("主要操作") { }
                            .buttonStyle(NativePrimaryButtonStyle())
                        Button("次要操作") { }
                            .buttonStyle(NativeSecondaryButtonStyle())
                    }
                    TextField("统一输入字段", text: .constant(""))
                        .font(AppTheme.inputFont)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: AppTheme.controlRadius, style: .continuous)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 0.8)
                        }
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("标准卡片").font(AppTheme.cardTitleFont)
                            Text("业务页面应直接复用这里展示的全局字号、颜色和圆角。")
                                .font(AppTheme.bodyFont)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .nativeCard()
                }
            }
            .padding(20)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("全局 UI 标准")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func standardSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(AppTheme.sectionTitleFont)
            VStack(alignment: .leading, spacing: 12) { content() }
                .padding(16)
                .background(Color.white, in: RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
                }
        }
    }

    private func fontSample(_ title: String, detail: String, font: Font) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(font)
            Spacer()
            Text(detail).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
        }
    }

    private func colorSample(_ title: String, _ color: Color) -> some View {
        VStack(spacing: 6) {
            Circle().fill(color).frame(width: 28, height: 28)
            Text(title).font(AppTheme.auxiliaryFont).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
