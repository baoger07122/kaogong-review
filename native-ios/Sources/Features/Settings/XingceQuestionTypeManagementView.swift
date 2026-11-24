import SwiftUI

struct XingceQuestionTypeManagementView: View {
    private var subjects: [SubjectDefinition] {
        SubjectDefinition.all.filter { $0.name != "申论" }
    }

    var body: some View {
        List {
            ForEach(subjects) { subject in
                NavigationLink(value: SettingsRoute.xingceQuestionTypeSubject(subject.name)) {
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
                .accessibilityIdentifier("settings-error-type-subject-\(subject.name)")
            }
        }
        .navigationTitle("题型管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}
