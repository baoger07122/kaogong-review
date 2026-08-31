import SwiftData
import SwiftUI
import UIKit

private struct ReviewAnswer { let selected: String; let correct: Bool }

private struct ReviewSessionSnapshot: Codable {
    let queueIDs: [String]
    let index: Int
}

private struct ReviewModuleStat: Identifiable {
    let subject: String
    let module: String
    let total: Int
    let inPool: Int
    let mastered: Int
    var id: String { "\(subject)|\(module)" }
}

struct ReviewView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Query private var records: [StoredRecord]
    @State private var queueIDs: [String] = []
    @State private var index = 0
    @State private var answer: ReviewAnswer?
    @State private var isSession = false
    private let sessionKey = "native.review.activeSession"

    private var errors: [StoredRecord] { records.filter { $0.collection == "errors" } }
    private var due: [StoredRecord] {
        errors.filter {
            let object = $0.jsonObject ?? [:]
            guard (object["status"] as? String) == "未掌握" else { return false }
            let date = parseDate(object["lastReviewDate"]) ?? $0.createdAt ?? .distantPast
            return Calendar.current.dateComponents([.day], from: date, to: .now).day ?? 0 >= 3
        }
        .sorted { reviewDate($0) < reviewDate($1) }
    }
    private var reviewPool: [StoredRecord] { due.isEmpty ? errors : due }
    private var queue: [StoredRecord] { queueIDs.compactMap { id in errors.first { $0.recordID == id } } }

    var body: some View {
        Group { if isSession { sessionView } else { homeView } }
            .background(AppTheme.groupedBackground)
            .navigationTitle(isSession ? "复习训练" : "复习")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear(perform: restoreSession)
            .onChange(of: queueIDs) { _, _ in persistSession() }
            .onChange(of: index) { _, _ in persistSession() }
            .onChange(of: isSession) { _, _ in persistSession() }
            .onChange(of: scenePhase) { _, phase in
                if phase != .active { persistSession() }
            }
    }

    private var homeView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("REVIEW MODE").font(AppTheme.auxiliaryFont.weight(.bold)).foregroundStyle(AppTheme.accent)
                    Text("今日复习").font(AppTheme.pageTitleFont)
                    Text("重新抽取历史错题，及时巩固薄弱知识点").font(AppTheme.bodyFont).foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    overview("待复习", due.count, due.isEmpty ? "暂无到期错题" : "超过3天未复习")
                    overview("本轮题量", reviewPool.count, "可按科目开始")
                    overview("已掌握", errors.filter { ($0.jsonObject?["status"] as? String) == "已掌握" }.count, "历史累计")
                }
                Text(due.isEmpty ? (errors.isEmpty ? "还没有可复习的错题" : "当前没有到期错题，先展示全部历史错题") : "优先显示超过3天未复习的错题")
                    .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                VStack(spacing: 9) {
                    ForEach(SubjectDefinition.all) { subject in
                        let count = reviewPool.filter { $0.subject == subject.name }.count
                        Button { start(subject: subject.name) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: subject.systemImage).foregroundStyle(subject.color)
                                    .frame(width: 38, height: 38).background(subject.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 11))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(subject.name).font(AppTheme.cardTitleFont).foregroundStyle(.primary)
                                    Text("\(count) 题待复习").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary)
                                }
                                Spacer(); Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(.tertiary)
                            }.nativeCard()
                        }.buttonStyle(.plain).disabled(count == 0)
                    }
                }
                if !moduleStats.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("模块复习概览").font(AppTheme.sectionTitleFont)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                            ForEach(moduleStats) { stat in
                                Button { start(subject: stat.subject, module: stat.module) } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(stat.module.isEmpty ? stat.subject : stat.module)
                                            .font(AppTheme.inputFont.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                                        Text("\(stat.subject) · 共 \(stat.total) 题")
                                            .font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(1)
                                        HStack {
                                            Label("\(stat.inPool)", systemImage: "clock.arrow.circlepath")
                                            Spacer()
                                            Label("\(stat.mastered)", systemImage: "checkmark.circle")
                                        }
                                        .font(AppTheme.auxiliaryFont)
                                        .foregroundStyle(AppTheme.accent)
                                    }
                                    .nativeCard()
                                }
                                .buttonStyle(.plain)
                                .disabled(stat.inPool == 0)
                            }
                        }
                    }
                }
                Button("开始全部复习") { start(subject: nil) }
                    .buttonStyle(NativePrimaryButtonStyle()).disabled(reviewPool.isEmpty)
            }.padding(20)
        }
    }

    private var sessionView: some View {
        Group { if index >= queue.count { finishedView } else { questionView(queue[index]) } }
    }

    private var moduleStats: [ReviewModuleStat] {
        let keys = Set(errors.map { "\($0.subject ?? "未分类")|\($0.module ?? "")" })
        return keys.map { key in
            let parts = key.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
            let subject = parts.first ?? "未分类"
            let module = parts.count > 1 ? parts[1] : ""
            let all = errors.filter { ($0.subject ?? "未分类") == subject && ($0.module ?? "") == module }
            let pool = reviewPool.filter { ($0.subject ?? "未分类") == subject && ($0.module ?? "") == module }
            return ReviewModuleStat(
                subject: subject,
                module: module,
                total: all.count,
                inPool: pool.count,
                mastered: all.filter { ($0.jsonObject?["status"] as? String) == "已掌握" }.count
            )
        }
        .sorted { $0.subject == $1.subject ? $0.module < $1.module : $0.subject < $1.subject }
    }

    private func questionView(_ record: StoredRecord) -> some View {
        let object = record.jsonObject ?? [:]
        let options = (object["options"] as? [String] ?? []).filter { !$0.isEmpty }
        let correctOption = object["correctOption"] as? String ?? ""
        return ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack { Button { exitSession() } label: { Label("退出", systemImage: "chevron.left") }; Spacer(); Text("第 \(index + 1) / \(queue.count) 题").font(AppTheme.inputFont.weight(.semibold)) }
                ProgressView(value: Double(index + 1), total: Double(max(1, queue.count))).tint(AppTheme.accent)
                Text([record.subject, record.module].compactMap { $0 }.joined(separator: " · ")).font(AppTheme.auxiliaryFont.weight(.semibold)).foregroundStyle(AppTheme.accent)
                Text(object["question"] as? String ?? "暂无题干").font(AppTheme.bodyFont).fixedSize(horizontal: false, vertical: true)
                if options.isEmpty {
                    NativeStatusCard(title: "这道错题没有选项", detail: "查看原题后，可直接标记为已复习。", systemImage: "doc.text", color: AppTheme.accent)
                    Button("标记为已复习") { submit(record: record, selected: correctOption) }.buttonStyle(NativePrimaryButtonStyle()).disabled(answer != nil)
                } else {
                    VStack(spacing: 9) {
                        ForEach(Array(options.enumerated()), id: \.offset) { offset, option in
                            let letter = String(UnicodeScalar(65 + offset)!)
                            Button { submit(record: record, selected: letter) } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(letter).font(AppTheme.inputFont.weight(.bold)).foregroundStyle(AppTheme.accent).frame(width: 27, height: 27).background(AppTheme.accent.opacity(0.10), in: Circle())
                                    Text(option).font(AppTheme.bodyFont).foregroundStyle(.primary).frame(maxWidth: .infinity, alignment: .leading)
                                }.padding(12).background(optionBackground(letter: letter, correct: correctOption), in: RoundedRectangle(cornerRadius: 12))
                            }.buttonStyle(.plain).disabled(answer != nil)
                        }
                    }
                }
                if let answer {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(answer.correct ? "回答正确" : "回答错误").font(AppTheme.cardTitleFont).foregroundStyle(answer.correct ? AppTheme.success : AppTheme.danger)
                        Text("正确答案：\(correctOption.isEmpty ? "未记录" : correctOption)").font(AppTheme.bodyFont)
                        if let cause = object["errorCause"] as? String, !cause.isEmpty { Text("错因：\(cause)").font(AppTheme.auxiliaryFont).foregroundStyle(.secondary) }
                    }.nativeCard()
                    Button(index + 1 >= queue.count ? "完成本轮" : "下一题") { index += 1; self.answer = nil }.buttonStyle(NativePrimaryButtonStyle())
                }
            }.padding(20)
        }
    }

    private var finishedView: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill").font(.system(size: 54)).foregroundStyle(AppTheme.success)
            Text("本轮复习完成").font(AppTheme.pageTitleFont)
            Text("这组错题已经重新训练一遍。" ).font(AppTheme.bodyFont).foregroundStyle(.secondary)
            Button("返回复习首页", action: exitSession).buttonStyle(NativePrimaryButtonStyle()).frame(maxWidth: 260)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func overview(_ title: String, _ value: Int, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(value)").font(.system(size: 23, weight: .semibold)).monospacedDigit(); Text(title).font(AppTheme.inputFont.weight(.semibold)); Text(detail).font(AppTheme.auxiliaryFont).foregroundStyle(.secondary).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading).nativeCard()
    }
    private func start(subject: String?, module: String? = nil) {
        queueIDs = reviewPool.filter {
            (subject == nil || $0.subject == subject) && (module == nil || ($0.module ?? "") == module)
        }.map(\.recordID)
        index = 0
        answer = nil
        isSession = true
        persistSession()
    }
    private func exitSession() { isSession = false; queueIDs = []; index = 0; answer = nil; UserDefaults.standard.removeObject(forKey: sessionKey) }

    private func persistSession() {
        guard isSession, !queueIDs.isEmpty, index < queueIDs.count else {
            if !isSession { UserDefaults.standard.removeObject(forKey: sessionKey) }
            return
        }
        let snapshot = ReviewSessionSnapshot(queueIDs: queueIDs, index: index)
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    private func restoreSession() {
        guard !isSession,
              let data = UserDefaults.standard.data(forKey: sessionKey),
              let snapshot = try? JSONDecoder().decode(ReviewSessionSnapshot.self, from: data)
        else { return }
        let existingIDs = Set(errors.map(\.recordID))
        let validQueue = snapshot.queueIDs.filter(existingIDs.contains)
        guard !validQueue.isEmpty, snapshot.index < validQueue.count else {
            UserDefaults.standard.removeObject(forKey: sessionKey)
            return
        }
        queueIDs = validQueue
        index = max(0, snapshot.index)
        answer = nil
        isSession = true
    }
    private func submit(record: StoredRecord, selected: String) {
        guard answer == nil else { return }
        var object = record.jsonObject ?? [:]
        let correctOption = object["correctOption"] as? String ?? ""
        let correct = !correctOption.isEmpty && selected == correctOption
        object["userOption"] = selected; object["reviewCount"] = ((object["reviewCount"] as? NSNumber)?.intValue ?? 0) + 1
        object["lastReviewDate"] = ISO8601DateFormatter().string(from: .now); object["updatedAt"] = ISO8601DateFormatter().string(from: .now); object["status"] = correct ? "已掌握" : "未掌握"
        if let payload = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) { record.payload = payload; record.updatedAt = .now; try? modelContext.save() }
        UINotificationFeedbackGenerator().notificationOccurred(correct ? .success : .error); answer = ReviewAnswer(selected: selected, correct: correct)
    }
    private func optionBackground(letter: String, correct: String) -> Color {
        guard let answer else { return AppTheme.secondaryBackground }; if letter == correct { return AppTheme.success.opacity(0.10) }; if letter == answer.selected { return AppTheme.danger.opacity(0.10) }; return AppTheme.secondaryBackground
    }
    private func reviewDate(_ record: StoredRecord) -> Date {
        parseDate(record.jsonObject?["lastReviewDate"]) ?? record.createdAt ?? .distantPast
    }
    private func parseDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            let seconds = number.doubleValue > 10_000_000_000 ? number.doubleValue / 1_000 : number.doubleValue
            return Date(timeIntervalSince1970: seconds)
        }
        guard let value = value as? String else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
