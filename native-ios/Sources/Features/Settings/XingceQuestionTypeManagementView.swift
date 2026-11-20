import SwiftUI

struct XingceQuestionTypeManagementView: View {
    private var subjects: [SubjectDefinition] {
        SubjectDefinition.all.filter { $0.name != "申论" }
    }

    var body: some View {
        List {
            ForEach(subjects) { subject in
                NavigationLink {
                    destination(for: subject.name)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: subject.systemImage)
                            .foregroundStyle(subject.color)
                            .frame(width: 22)
                        Text(subject.name)
                            .font(.system(size: 14, weight: .regular))
                            .foregroundStyle(.primary)
                        Spacer(minLength: 12)
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("题型管理")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func destination(for name: String) -> some View {
        if name == "数量关系" {
            QuantityQuestionTypeManagerView()
        } else if let subject = LibraryErrorTypeSubject(rawValue: name) {
            LibraryErrorTypeModulesView(subject: subject)
        } else {
            ContentUnavailableView("暂无题型目录", systemImage: "square.stack.3d.up")
        }
    }
}
