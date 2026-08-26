import SwiftData
import SwiftUI

struct LibraryView: View {
    @Query private var records: [StoredRecord]
    @State private var searchText = ""

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 2), spacing: 14) {
                ForEach(filteredSubjects) { subject in
                    NavigationLink {
                        SubjectLibraryView(subject: subject)
                    } label: {
                        subjectCard(subject)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
        }
        .background(AppTheme.groupedBackground)
        .navigationTitle("学习库")
        .searchable(text: $searchText, prompt: "搜索科目")
    }

    private var filteredSubjects: [SubjectDefinition] {
        guard !searchText.isEmpty else { return SubjectDefinition.all }
        return SubjectDefinition.all.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    private func collectionCount(_ collection: String, subject: String) -> Int {
        records.lazy.filter { $0.collection == collection && $0.subject == subject }.count
    }

    private func subjectCard(_ subject: SubjectDefinition) -> some View {
        HStack(spacing: 16) {
            Image(systemName: subject.systemImage)
                .font(.title2)
                .foregroundStyle(subject.color)
                .frame(width: 48, height: 48)
                .background(subject.color.opacity(0.13), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(subject.name).font(.headline)
                Text("\(collectionCount("errors", subject: subject.name)) 错题 · \(collectionCount("notes", subject: subject.name)) 笔记")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(.tertiary)
        }
        .nativeCard()
    }
}

struct SubjectLibraryView: View {
    let subject: SubjectDefinition
    @Query private var records: [StoredRecord]

    var body: some View {
        List(subject.modules, id: \.self) { module in
            NavigationLink {
                ModuleLibraryView(subject: subject.name, module: module)
            } label: {
                HStack {
                    Text(module).font(.headline)
                    Spacer()
                    Text("\(count("errors", module: module)) 题 · \(count("notes", module: module)) 笔记")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
        .navigationTitle(subject.name)
    }

    private func count(_ collection: String, module: String) -> Int {
        records.lazy.filter { $0.collection == collection && $0.subject == subject.name && $0.module == module }.count
    }
}

struct ModuleLibraryView: View {
    enum ContentKind: String, CaseIterable, Identifiable {
        case all = "全部"
        case errors = "错题"
        case notes = "笔记"
        case stickies = "便签"
        var id: String { rawValue }
    }

    let subject: String
    let module: String
    @Query private var records: [StoredRecord]
    @State private var kind: ContentKind = .all

    private var filtered: [StoredRecord] {
        records.filter { record in
            guard record.subject == subject && record.module == module else { return false }
            switch kind {
            case .all: return ["errors", "notes", "stickies"].contains(record.collection)
            case .errors: return record.collection == "errors"
            case .notes: return record.collection == "notes"
            case .stickies: return record.collection == "stickies"
            }
        }
        .sorted { ($0.updatedAt ?? $0.createdAt ?? .distantPast) > ($1.updatedAt ?? $1.createdAt ?? .distantPast) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("内容类型", selection: $kind) {
                ForEach(ContentKind.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            if filtered.isEmpty {
                ContentUnavailableView("暂无\(kind.rawValue)", systemImage: "tray", description: Text("导入备份后可在这里核对模块数据。"))
            } else {
                List(filtered, id: \.compoundID) { record in
                    NavigationLink { RecordJSONDetailView(record: record) } label: { RecordRow(record: record) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(module)
        .navigationBarTitleDisplayMode(.inline)
    }
}
