import SwiftUI
import UIKit

struct GraphReasoningFlashcardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let records: [LibraryRecordSnapshot]
    let onEdit: (LibraryRecordSnapshot) -> Void
    @State private var index = 0
    @State private var showsBack = false

    private var current: LibraryRecordSnapshot { records[min(index, max(0, records.count - 1))] }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("图形推理闪卡").font(AppTheme.sectionTitleFont)
                Spacer()
                Text("\(index + 1) / \(records.count)").font(AppTheme.auxiliaryFont.monospacedDigit()).foregroundStyle(.secondary)
            }

            ZStack {
                if showsBack { back(current) } else { front(current) }
            }
            .frame(maxWidth: .infinity, minHeight: 330, alignment: .topLeading)
            .padding(18)
            .background(AppTheme.secondaryBackground, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.primary.opacity(0.07), lineWidth: 0.7))
            .rotation3DEffect(.degrees(reduceMotion ? 0 : (showsBack ? 360 : 0)), axis: (x: 0, y: 1, z: 0))
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.42, bounce: 0.16)) { showsBack.toggle() }
            }
            .accessibilityHint("轻点查看\(showsBack ? "正面" : "答案与解析")")

            HStack(spacing: 12) {
                Button { move(-1) } label: { Label("上一张", systemImage: "chevron.left") }
                    .buttonStyle(NativeSecondaryButtonStyle()).disabled(index == 0)
                Button { onEdit(current) } label: { Label("编辑", systemImage: "pencil") }
                    .buttonStyle(NativeSecondaryButtonStyle())
                Button { move(1) } label: { Label("下一张", systemImage: "chevron.right") }
                    .buttonStyle(NativeSecondaryButtonStyle()).disabled(index == records.count - 1)
            }
        }
        .onChange(of: records.map(\.id)) { _, _ in
            index = min(index, max(0, records.count - 1))
            showsBack = false
        }
    }

    private func front(_ snapshot: LibraryRecordSnapshot) -> some View {
        let object = snapshot.record.jsonObject ?? [:]
        let images = imageValues(object)
        let options = object["options"] as? [String] ?? []
        return VStack(alignment: .leading, spacing: 14) {
            HStack { Text("正面").font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent); Spacer(); Text("轻点翻面").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
            if !images.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(images.enumerated()), id: \.offset) { _, value in GraphFlashImage(value: value) }
                    }
                }
            }
            Text(snapshot.title).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                        HStack(alignment: .top, spacing: 8) {
                            Text(String(UnicodeScalar(65 + offset)!)).font(AppTheme.auxiliaryFont.weight(.bold)).foregroundStyle(AppTheme.accent)
                                .frame(width: 23, height: 23).background(AppTheme.accent.opacity(0.10), in: Circle())
                            Text(option).font(AppTheme.inputFont)
                        }
                    }
                }
            }
        }
    }

    private func back(_ snapshot: LibraryRecordSnapshot) -> some View {
        let object = snapshot.record.jsonObject ?? [:]
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("背面").font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent); Spacer(); Text("轻点翻回").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                answerRow("正确答案", value: text(object, "correctOption"), color: AppTheme.success)
                answerRow("我的答案", value: text(object, "userOption"), color: AppTheme.danger)
                detail("考点", text(object, "knowledgePoint"))
                detail("图形规律", text(object, "graphRule", fallback: "patternRule"))
                detail("识别思路", text(object, "recognition", fallback: "recognitionPath"))
                detail("错因", text(object, "errorCause"))
                detail("易错点", text(object, "pitfall"))
                detail("复盘笔记", text(object, "note"))
                detail("题目来源", text(object, "questionSource"))
                HStack {
                    Text(text(object, "status").isEmpty ? "未掌握" : text(object, "status"))
                        .font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.warning)
                    Spacer()
                    if let date = snapshot.createdAt { Text(date, format: .dateTime.year().month().day()).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                }
            }
        }
    }

    private func answerRow(_ title: String, value: String, color: Color) -> some View {
        HStack { Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary); Spacer(); Text(value.isEmpty ? "未填写" : value).font(AppTheme.bodyFont.weight(.semibold)).foregroundStyle(color) }
            .padding(10).background(color.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
    }

    @ViewBuilder private func detail(_ title: String, _ value: String) -> some View {
        if !value.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                Text(plainText(value)).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func move(_ offset: Int) {
        index = min(max(0, index + offset), records.count - 1)
        showsBack = false
    }
    private func text(_ object: [String: Any], _ key: String, fallback: String? = nil) -> String {
        (object[key] as? String) ?? fallback.flatMap { object[$0] as? String } ?? ""
    }
    private func imageValues(_ object: [String: Any]) -> [String] {
        (object["images"] as? [String]) ?? (object["image"] as? String).map { [$0] } ?? []
    }
    private func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct GraphFlashImage: View {
    let value: String
    var body: some View {
        Group {
            if let image = localImage {
                Image(uiImage: image).resizable().scaledToFit()
            } else if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { ProgressView() }
            } else {
                Image(systemName: "photo").font(.system(size: 28)).foregroundStyle(.secondary)
            }
        }
        .frame(width: 210, height: 150)
        .background(Color.white, in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
    private var localImage: UIImage? {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...])).flatMap(UIImage.init(data:))
    }
}
