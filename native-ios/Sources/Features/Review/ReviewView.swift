import SwiftData
import SwiftUI

struct ReviewView: View {
    @Query private var records: [StoredRecord]

    private var errors: [StoredRecord] { records.filter { $0.collection == "errors" } }
    private var unmastered: [StoredRecord] {
        errors.filter { ($0.jsonObject?["status"] as? String) != "已掌握" }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("REVIEW MODE")
                        .font(.caption.bold())
                        .foregroundStyle(AppTheme.accent)
                    Text("今日复习").font(.largeTitle.bold())
                    Text("第一阶段先核对旧错题数量，训练流程将在错题原生模型完成后接入。")
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    overview(title: "待复习", value: unmastered.count, subtitle: "未掌握错题")
                    overview(title: "历史错题", value: errors.count, subtitle: "已导入总数")
                }

                NativeSectionHeader(title: "按科目")
                VStack(spacing: 10) {
                    ForEach(SubjectDefinition.all) { subject in
                        let count = unmastered.lazy.filter { $0.subject == subject.name }.count
                        HStack(spacing: 14) {
                            Image(systemName: subject.systemImage)
                                .foregroundStyle(subject.color)
                                .frame(width: 40, height: 40)
                                .background(subject.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                            Text(subject.name).font(.headline)
                            Spacer()
                            Text("\(count) 题").foregroundStyle(.secondary)
                            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
                        }
                        .nativeCard()
                    }
                }

                Button("开始复习（下一阶段开放）") { }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                    .frame(maxWidth: .infinity)
            }
            .padding(24)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("复习")
    }

    private func overview(title: String, value: Int, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("\(value)").font(.largeTitle.bold())
            Text(title).font(.headline)
            Text(subtitle).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .nativeCard()
    }
}

