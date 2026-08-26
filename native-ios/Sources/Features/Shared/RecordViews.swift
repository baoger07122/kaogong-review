import SwiftUI

struct RecordRow: View {
    let record: StoredRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(record.title)
                .font(.headline)
                .lineLimit(2)
            HStack(spacing: 8) {
                Text(record.collection)
                if let subject = record.subject, !subject.isEmpty { Text(subject) }
                if let module = record.module, !module.isEmpty { Text(module) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

struct RecordJSONDetailView: View {
    let record: StoredRecord

    private var prettyJSON: String {
        guard
            let object = try? JSONSerialization.jsonObject(with: record.payload),
            let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else { return "无法读取原始记录" }
        return string
    }

    var body: some View {
        ScrollView {
            Text(prettyJSON)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(record.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NativePlaceholderView: View {
    let title: String
    let detail: String
    var systemImage: String = "hammer"

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(detail))
            .navigationTitle(title)
    }
}

