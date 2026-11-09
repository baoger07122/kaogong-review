import SwiftData
import SwiftUI

struct HomeShortcutView: View {
    let route: AppRoute

    @ViewBuilder
    var body: some View {
        switch route {
        case .todoStats:
            TodoStatsView()
        case .studyReport:
            StudyReportView()
        case .wordReview:
            WordReviewView()
        case let .wordReviewWordDetail(recordID):
            WordReviewWordDetailDestination(recordID: recordID)
        case let .errorDetail(recordID):
            HomeErrorDetailDestination(recordID: recordID)
        case .speedPractice:
            SpeedPracticeView()
                .secondaryPageTabBarHidden()
        case .exams:
            ExamsView()
        case .currentAffairs:
            CurrentAffairsView()
        case .knowledgePoints:
            KnowledgePointManagerView()
        default:
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch route {
                    default:
                        placeholder(title: "功能建设中", detail: "当前路由尚未进入正式重写阶段。", image: "hammer")
                    }
                }
                .padding(20)
            }
            .background(Color.white)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var title: String {
        switch route {
        case .todoStats: "待办统计"
        case .studyReport: "学习报告"
        case .wordReview: "词语复习"
        case .wordReviewWordDetail: "词语详情"
        case .errorDetail: "错题详情"
        case .speedPractice: "速算练习"
        case .exams: "套卷记录"
        case .currentAffairs: "时政常识"
        case .knowledgePoints: "考点管理"
        default: "功能"
        }
    }
    private func placeholder(title: String, detail: String, image: String) -> some View {
        NativeStatusCard(title: title, detail: detail, systemImage: image, color: AppTheme.accent)
    }
}

private struct HomeErrorDetailDestination: View {
    let recordID: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<StoredRecord> { record in
        record.collection == "errors"
            || record.collection == "words"
            || record.collection == "notes"
            || record.collection == "exams"
    }) private var records: [StoredRecord]
    @StateObject private var doodleSession = LibraryDoodleSession()
    @State private var isShowingEditor = false
    @State private var isShowingAdaptation = false

    private var record: StoredRecord? {
        records.first { $0.collection == "errors" && $0.recordID == recordID }
    }

    var body: some View {
        Group {
            if let record {
                if record.isShenlunRecord {
                    ShenlunRecordDetailView(
                        record: record,
                        onEdit: { isShowingAdaptation = record.requiresShenlunAdaptation; isShowingEditor = !record.requiresShenlunAdaptation },
                        onDelete: { delete(record) }
                    )
                    .environmentObject(doodleSession)
                } else {
                    LibraryRecordDetailView(
                        kind: .errors,
                        scope: scope(for: record),
                        record: record,
                        onEdit: { isShowingEditor = true },
                        onDelete: { delete(record) }
                    )
                    .environmentObject(doodleSession)
                }
            } else {
                ContentUnavailableView("错题已删除", systemImage: "xmark.circle", description: Text("这条错题已从题库移除。"))
            }
        }
        .navigationDestination(isPresented: $isShowingEditor) {
            if let record {
                LibraryRecordEditorView(kind: .errors, scope: scope(for: record), record: record)
            }
        }
        .navigationDestination(isPresented: $isShowingAdaptation) {
            if let record {
                ShenlunAdaptationView(record: record) { isShowingAdaptation = false }
            }
        }
    }

    private func scope(for record: StoredRecord) -> LibraryScope {
        LibraryScope(
            subject: record.subject,
            module: record.module,
            reviewSource: LibraryReviewSource.explicitValue(in: record.jsonObject ?? [:]) ?? .real
        )
    }

    private func delete(_ record: StoredRecord) {
        do {
            try LibraryRecordRepository.remove(kind: .errors, id: record.recordID, records: records, context: modelContext)
            dismiss()
        } catch {
            NativePerformanceLog.event("linked error delete failed: \(error.localizedDescription)")
        }
    }
}
