import SwiftUI

struct SpeedEstimateTableView: View {
    let rows: [SpeedEstimateRow]
    let onSave: ([SpeedEstimateRow]) throws -> Void
    @State private var draft: SpeedEstimateRow?
    @State private var error: String?

    var body: some View {
        let ordered = SpeedEstimateRules.sorted(rows)
        let gaps = SpeedEstimateRules.uncovered(rows)
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("范围 → 估算值").font(.system(size: 17, weight: .semibold))
                    Spacer()
                    Button {
                        let next = gaps.first?.lowerBound ?? 101
                        draft = .init(id: UUID().uuidString, minimum: next, maximum: next, value: SpeedEstimateRules.approximation(for: next, rows: []).value)
                    } label: {
                        Label("新增", systemImage: "plus").font(.system(size: 13, weight: .medium))
                            .padding(.horizontal, 14).frame(height: 34)
                            .foregroundStyle(.white).background(Color.blue, in: Capsule())
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityIdentifier("estimate-add")
                }
                Text("按起始数字自动排序 · 区间包含两端")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Text("范围")
                    Spacer()
                    Text("估算值").padding(.trailing, 64)
                }.font(.system(size: 13)).foregroundStyle(.secondary)
                if ordered.isEmpty {
                    Text("尚未定义区间。未覆盖的数字暂用系统估算，不会自动写入此表。")
                        .font(.system(size: 13)).foregroundStyle(.secondary).padding(.vertical, 30)
                }
                ForEach(ordered) { row in
                    HStack(spacing: 8) {
                        Button { draft = row } label: {
                            HStack {
                                Text("\(row.minimum) – \(row.maximum)").foregroundStyle(Color.primary)
                                Spacer()
                                Text("\(row.value)").fontWeight(.semibold).foregroundStyle(.blue)
                            }
                            .font(.system(size: 16)).frame(maxWidth: .infinity, minHeight: 48)
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                        Button(role: .destructive) { persist(rows.filter { $0.id != row.id }) } label: {
                            Image(systemName: "trash").frame(width: 44, height: 44).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("删除 \(row.minimum) 至 \(row.maximum)")
                    }
                    .padding(.horizontal, 14)
                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("estimate-row-\(row.minimum)")
                }
                Text("已定义 \(899 - gaps.reduce(0) { $0 + $1.count }) / 899 个数字")
                    .font(.system(size: 13, weight: .medium)).padding(.top, 8)
                Text(gaps.isEmpty ? "101–999 已全部覆盖" : "未覆盖：" + gaps.map { $0.lowerBound == $0.upperBound ? "\($0.lowerBound)" : "\($0.lowerBound)–\($0.upperBound)" }.joined(separator: "、"))
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                Text("未定义时，系统优先取最近的整十数或 125 的倍数；练习中会明确标注来源。")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                if let issue = SpeedEstimateRules.validationError(rows) {
                    Text(issue).font(.system(size: 12)).foregroundStyle(.red)
                }
            }.padding(16)
        }
        .disabled(draft != nil)
        .overlay {
            if let draft {
                SpeedEstimateRowEditor(row: draft, existing: rows, onClose: { self.draft = nil }) { updated in
                    let next = SpeedEstimateRules.sorted(rows.filter { $0.id != updated.id } + [updated])
                    try onSave(next)
                    self.draft = nil
                }
                .id(draft.id)
            }
        }
        .alert("估算表未保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("知道了", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func persist(_ value: [SpeedEstimateRow]) {
        do { try onSave(SpeedEstimateRules.sorted(value)) }
        catch { self.error = error.localizedDescription }
    }
}

private struct SpeedEstimateRowEditor: View {
    let row: SpeedEstimateRow
    let existing: [SpeedEstimateRow]
    let onClose: () -> Void
    let onSave: (SpeedEstimateRow) throws -> Void
    @State private var minimum: String
    @State private var maximum: String
    @State private var value: String
    @State private var error: String?

    init(row: SpeedEstimateRow, existing: [SpeedEstimateRow], onClose: @escaping () -> Void, onSave: @escaping (SpeedEstimateRow) throws -> Void) {
        self.row = row; self.existing = existing; self.onClose = onClose; self.onSave = onSave
        _minimum = State(initialValue: String(row.minimum))
        _maximum = State(initialValue: String(row.maximum))
        _value = State(initialValue: String(row.value))
    }

    var body: some View {
        NativeEditorDialog(title: existing.contains { $0.id == row.id } ? "编辑估算区间" : "新增估算区间", canSave: true, onClose: onClose, onSave: save) {
            HStack(spacing: 10) {
                field("起始数字", text: $minimum, id: "estimate-minimum")
                Text("–")
                field("结束数字", text: $maximum, id: "estimate-maximum")
            }
            field("估算值", text: $value, id: "estimate-value")
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
        }
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape, onClose)
    }

    private func field(_ title: String, text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12)).foregroundStyle(.secondary)
            TextField(title, text: text).font(.system(size: 13)).keyboardType(.numberPad)
                .textFieldStyle(NativeTextFieldStyle()).accessibilityIdentifier(id)
        }
    }

    private func save() {
        guard let a = Int(minimum), let b = Int(maximum), let v = Int(value) else { error = "请填写三个整数。"; return }
        let updated = SpeedEstimateRow(id: row.id, minimum: a, maximum: b, value: v)
        if let issue = SpeedEstimateRules.validationError(existing.filter { $0.id != row.id } + [updated]) { error = issue; return }
        do { try onSave(updated) } catch { self.error = error.localizedDescription }
    }
}
