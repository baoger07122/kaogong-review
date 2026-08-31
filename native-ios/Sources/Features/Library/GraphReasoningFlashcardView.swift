import SwiftUI
import UIKit

struct GraphReasoningFlashcardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let records: [LibraryRecordSnapshot]
    let onEdit: (LibraryRecordSnapshot) -> Void
    @State private var index = 0
    @State private var showsBack = false
    @State private var submittedAnswer: String?
    @State private var previewImage: GraphImagePreviewItem?

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
            submittedAnswer = nil
        }
        .fullScreenCover(item: $previewImage) { item in
            GraphImagePreviewView(value: item.value)
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
                        ForEach(Array(images.enumerated()), id: \.offset) { _, value in
                            Button { previewImage = GraphImagePreviewItem(value: value) } label: {
                                GraphFlashImage(value: value)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("全屏查看题目图片")
                        }
                    }
                }
            }
            Text(snapshot.title).font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
            if !options.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                        let letter = String(UnicodeScalar(65 + offset)!)
                        Button { submit(snapshot, answer: letter) } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text(letter).font(AppTheme.auxiliaryFont.weight(.bold)).foregroundStyle(AppTheme.accent)
                                    .frame(width: 23, height: 23).background(AppTheme.accent.opacity(0.10), in: Circle())
                                Text(option).font(AppTheme.inputFont).foregroundStyle(.primary)
                                Spacer()
                            }
                            .padding(8)
                            .background(submittedAnswer == letter ? AppTheme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .disabled(submittedAnswer != nil)
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
        submittedAnswer = nil
    }

    private func submit(_ snapshot: LibraryRecordSnapshot, answer: String) {
        guard submittedAnswer == nil else { return }
        var object = snapshot.record.jsonObject ?? [:]
        let correctAnswer = object["correctOption"] as? String ?? ""
        let correct = !correctAnswer.isEmpty && answer == correctAnswer
        let now = ISO8601DateFormatter().string(from: .now)
        object["userOption"] = answer
        object["reviewCount"] = ((object["reviewCount"] as? NSNumber)?.intValue ?? 0) + 1
        object["lastReviewDate"] = now
        object["updatedAt"] = now
        object["status"] = correct ? "已掌握" : "未掌握"
        guard let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        snapshot.record.payload = payload
        snapshot.record.updatedAt = .now
        try? modelContext.save()
        submittedAnswer = answer
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error)
        withAnimation(reduceMotion ? .easeInOut(duration: 0.12) : .spring(duration: 0.38, bounce: 0.12)) {
            showsBack = true
        }
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

private struct GraphImagePreviewItem: Identifiable {
    let id = UUID()
    let value: String
}

private struct GraphImagePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    let value: String
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            image
                .scaleEffect(scale)
                .offset(offset)
                .gesture(
                    MagnifyGesture()
                        .onChanged { value in scale = min(6, max(1, lastScale * value.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale <= 1 { reset() }
                        }
                )
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            guard scale > 1 else { return }
                            offset = CGSize(width: lastOffset.width + value.translation.width, height: lastOffset.height + value.translation.height)
                        }
                        .onEnded { _ in lastOffset = offset }
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring(duration: 0.25, bounce: 0.05)) {
                        if scale > 1 { reset() } else { scale = 2; lastScale = 2 }
                    }
                }

            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(20)
        }
    }

    @ViewBuilder private var image: some View {
        if let image = localImage {
            Image(uiImage: image).resizable().scaledToFit().padding(24)
        } else if let url = URL(string: value), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
            AsyncImage(url: url) { phase in
                if let image = phase.image { image.resizable().scaledToFit().padding(24) }
                else if phase.error != nil { Image(systemName: "photo.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.white) }
                else { ProgressView().tint(.white) }
            }
        } else {
            Image(systemName: "photo.badge.exclamationmark").font(.system(size: 44)).foregroundStyle(.white)
        }
    }

    private var localImage: UIImage? {
        guard value.hasPrefix("data:"), let comma = value.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(value[value.index(after: comma)...])).flatMap(UIImage.init(data:))
    }

    private func reset() {
        scale = 1
        lastScale = 1
        offset = .zero
        lastOffset = .zero
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
