import Foundation
import SwiftData

struct ExamSubjectScore: Identifiable, Equatable {
    var subject: String
    var score: String
    var totalScore: String
    var id: String { subject }
}

struct ExamModuleResult: Identifiable, Codable, Equatable {
    var id: String
    var subject: String
    var parentSubject: String
    var totalQuestions: String
    var correctCount: String
    var reportedAccuracy: String
    var timeSeconds: String

    init(
        id: String = UUID().uuidString,
        subject: String,
        parentSubject: String? = nil,
        totalQuestions: String = "",
        correctCount: String = "",
        reportedAccuracy: String = "",
        timeSeconds: String = ""
    ) {
        self.id = id
        self.subject = subject
        self.parentSubject = parentSubject ?? ExamReportParser.parentSubject(for: subject)
        self.totalQuestions = totalQuestions
        self.correctCount = correctCount
        self.reportedAccuracy = reportedAccuracy
        self.timeSeconds = timeSeconds
    }

    var isTopLevel: Bool { subject == parentSubject }
    var validCounts: (total: Int, correct: Int)? {
        guard let total = Int(totalQuestions), let correct = Int(correctCount), total > 0, correct >= 0, correct <= total else { return nil }
        return (total, correct)
    }

    var payloadObject: [String: Any] {
        ["id": id, "subject": subject, "parentSubject": parentSubject,
         "totalQuestions": totalQuestions, "correctCount": correctCount,
         "reportedAccuracy": reportedAccuracy, "timeSeconds": timeSeconds]
    }
}

struct ExamDerivedMetrics {
    var totalQuestions: Int?
    var correctCount: Int?
    var wrongCount: Int? { totalQuestions.flatMap { total in correctCount.map { max(0, total - $0) } } }
    var accuracyPercent: Double?
    var totalTimeSeconds: Int?
    var conflictModules: Set<String>
    var hierarchyWarnings: [String]
}

struct ExamDraft {
    var original: [String: Any] = [:]
    var id = ""
    var examType: LibraryReviewSource = .real
    var name = ""
    var examDate = Date()
    var rawReport = ""
    var moduleResults: [ExamModuleResult] = []
    var score = ""
    var maximumScore = ""
    // Kept for legacy payload preservation; the new editor never derives score from these values.
    var subjectScores: [ExamSubjectScore] = []
    var totalAccuracy = ""
    var totalTime = ""
    var targetScore = ""
    var reviewNote = ""
    var linkedErrorIDs: Set<String> = []

    init(record: StoredRecord? = nil) {
        original = record?.jsonObject ?? [:]
        id = record?.recordID ?? ""
        examType = record == nil ? .real : (LibraryReviewSource.explicitValue(in: original) ?? .pending)
        name = original["name"] as? String ?? ""
        if let value = original["examDate"] as? String { examDate = Self.dayFormatter.date(from: value) ?? ISO8601DateFormatter().date(from: value) ?? .now }
        rawReport = original["rawReport"] as? String ?? ""
        if let values = original["moduleResults"] as? [[String: Any]] {
            moduleResults = values.compactMap { value in
                guard let subject = value["subject"] as? String else { return nil }
                return ExamModuleResult(
                    id: value["id"] as? String ?? UUID().uuidString,
                    subject: subject,
                    parentSubject: value["parentSubject"] as? String,
                    totalQuestions: Self.stringValue(value["totalQuestions"]),
                    correctCount: Self.stringValue(value["correctCount"]),
                    reportedAccuracy: Self.stringValue(value["reportedAccuracy"]),
                    timeSeconds: Self.stringValue(value["timeSeconds"])
                )
            }
        }
        if let values = original["subjectScores"] as? [[String: Any]] {
            subjectScores = values.compactMap {
                guard let subject = $0["subject"] as? String else { return nil }
                return ExamSubjectScore(subject: subject, score: Self.stringValue($0["score"]), totalScore: Self.stringValue($0["totalScore"]))
            }
        }
        totalAccuracy = Self.stringValue(original["totalAccuracy"])
        totalTime = Self.stringValue(original["totalTime"])
        targetScore = Self.stringValue(original["targetScore"])
        score = Self.stringValue(original["score"])
        maximumScore = Self.stringValue(original["maximumScore"])
        reviewNote = original["reviewNote"] as? String ?? ""
        linkedErrorIDs = Set(original["linkedErrorIds"] as? [String] ?? [])
    }

    var metrics: ExamDerivedMetrics { ExamReportParser.metrics(for: moduleResults) }

    static let dayFormatter: DateFormatter = {
        let value = DateFormatter()
        value.locale = Locale(identifier: "zh_CN")
        value.timeZone = TimeZone.current
        value.dateFormat = "yyyy-MM-dd"
        return value
    }()

    private static func stringValue(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let number = value as? NSNumber { return number.stringValue }
        return value as? String ?? ""
    }
}

enum ExamReportParser {
    struct Result {
        var lines: [ExamModuleResult]
        var unparsedLines: [String]
        var duplicateConflicts: [String]
    }

    private static let topLevelModules: Set<String> = [
        "政治理论", "常识判断", "言语理解与表达", "数量关系", "判断推理", "资料分析"
    ]

    static func parse(_ rawText: String) -> Result {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "：", with: ":")
        let pattern = #"^\s*[•·\-–—]?\s*(.+?)\s*共\s*(\d+)\s*(?:道|题)\s*[,、\s]*答对\s*(\d+)\s*(?:道|题)\s*[,、\s]*正确率\s*:?\s*(\d+(?:\.\d+)?)\s*%\s*[,、\s]*用时\s*:?\s*(.+?)\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return Result(lines: [], unparsedLines: [rawText], duplicateConflicts: [])
        }

        var parsed: [ExamModuleResult] = []
        var unparsed: [String] = []
        var seenBySubject: [String: ExamModuleResult] = [:]
        var conflicts = Set<String>()
        for line in normalized.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }).filter({ !$0.isEmpty }) {
            let nsLine = line as NSString
            let range = NSRange(location: 0, length: nsLine.length)
            guard let match = expression.firstMatch(in: line, range: range), match.numberOfRanges == 6 else {
                unparsed.append(line)
                continue
            }
            let subject = nsLine.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespacesAndNewlines)
            let total = nsLine.substring(with: match.range(at: 2))
            let correct = nsLine.substring(with: match.range(at: 3))
            let accuracy = nsLine.substring(with: match.range(at: 4))
            let time = nsLine.substring(with: match.range(at: 5))
            guard !subject.isEmpty, let seconds = parseTime(time) else {
                unparsed.append(line)
                continue
            }
            let value = ExamModuleResult(
                subject: subject,
                totalQuestions: total,
                correctCount: correct,
                reportedAccuracy: accuracy,
                timeSeconds: String(seconds)
            )
            if let previous = seenBySubject[subject] {
                if previous.subject == value.subject,
                   previous.totalQuestions == value.totalQuestions,
                   previous.correctCount == value.correctCount,
                   previous.reportedAccuracy == value.reportedAccuracy,
                   previous.timeSeconds == value.timeSeconds { continue }
                conflicts.insert(subject)
            } else {
                seenBySubject[subject] = value
            }
            parsed.append(value)
        }
        return Result(lines: parsed, unparsedLines: unparsed, duplicateConflicts: conflicts.sorted())
    }

    static func parentSubject(for subject: String) -> String {
        if topLevelModules.contains(subject) { return subject }
        switch subject {
        case "逻辑填空", "片段阅读", "语句表达": return "言语理解与表达"
        case "图形推理", "定义判断", "类比推理", "逻辑判断": return "判断推理"
        case "文字材料", "表格材料", "图表材料", "综合材料": return "资料分析"
        default: return subject
        }
    }

    static func parseTime(_ value: String) -> Int? {
        let clean = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if clean.contains(":") {
            let parts = clean
                .split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (parts.count == 2 || parts.count == 3),
                  parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            let values = parts.compactMap { Int($0) }
            guard values.count == parts.count, values.allSatisfy({ $0 >= 0 }) else { return nil }
            if values.count == 2 {
                let (minutes, overflow) = values[0].multipliedReportingOverflow(by: 60)
                let (seconds, additionOverflow) = minutes.addingReportingOverflow(values[1])
                guard values[1] < 60, !overflow, !additionOverflow else { return nil }
                return seconds
            }
            let (hours, hourOverflow) = values[0].multipliedReportingOverflow(by: 3600)
            let (minutes, minuteOverflow) = values[1].multipliedReportingOverflow(by: 60)
            let (partial, firstAdditionOverflow) = hours.addingReportingOverflow(minutes)
            let (seconds, secondAdditionOverflow) = partial.addingReportingOverflow(values[2])
            guard values[1] < 60, values[2] < 60,
                  !hourOverflow, !minuteOverflow, !firstAdditionOverflow, !secondAdditionOverflow else { return nil }
            return seconds
        }
        let expression = try? NSRegularExpression(pattern: #"(\d+)\s*(小时|时|分钟|分|秒)"#)
        let nsValue = clean as NSString
        let matches = expression?.matches(in: clean, range: NSRange(location: 0, length: nsValue.length)) ?? []
        guard !matches.isEmpty else { return nil }
        var total = 0
        for match in matches where match.numberOfRanges == 3 {
            guard let number = Int(nsValue.substring(with: match.range(at: 1))) else { return nil }
            let unit = nsValue.substring(with: match.range(at: 2))
            let multiplier: Int
            switch unit {
            case "小时", "时": multiplier = 3_600
            case "分钟", "分": multiplier = 60
            default: multiplier = 1
            }
            let (seconds, multiplicationOverflow) = number.multipliedReportingOverflow(by: multiplier)
            let (updatedTotal, additionOverflow) = total.addingReportingOverflow(seconds)
            guard !multiplicationOverflow, !additionOverflow else { return nil }
            total = updatedTotal
        }
        return total
    }

    static func metrics(for lines: [ExamModuleResult]) -> ExamDerivedMetrics {
        let allGrouped = Dictionary(grouping: lines) { "\($0.parentSubject)\u{1F}\($0.subject)" }
        let conflictKeys = Set(allGrouped.compactMap { $0.value.count > 1 ? $0.key : nil })
        let conflictModules = Set(allGrouped.compactMap { $0.value.count > 1 ? $0.value.first?.subject : nil })
        let topLevelGrouped = Dictionary(grouping: lines.filter(\.isTopLevel), by: \.subject)
        let parents = topLevelGrouped.compactMap { name, values -> ExamModuleResult? in
            guard values.count == 1 else { return nil }
            return values[0]
        }
        let countRows = parents.compactMap { row -> (Int, Int)? in
            guard let values = row.validCounts else { return nil }
            return (values.total, values.correct)
        }
        let totals = countRows.reduce(into: (total: 0, correct: 0)) { $0.total += $1.0; $0.correct += $1.1 }
        let hasQuestionData = !countRows.isEmpty
        let times = parents.compactMap { Int($0.timeSeconds) }.filter { $0 >= 0 }
        var warnings: [String] = []
        for parent in parents {
            let children = lines.filter { $0.parentSubject == parent.subject && !$0.isTopLevel }
            guard !children.isEmpty else { continue }
            guard !children.contains(where: { conflictKeys.contains("\($0.parentSubject)\u{1F}\($0.subject)") }) else { continue }
            if let parentCounts = parent.validCounts,
               children.allSatisfy({ $0.validCounts != nil }) {
                let childTotal = children.compactMap(\.validCounts).reduce(0) { $0 + $1.total }
                let childCorrect = children.compactMap(\.validCounts).reduce(0) { $0 + $1.correct }
                if parentCounts.total != childTotal || parentCounts.correct != childCorrect {
                    warnings.append("\(parent.subject)总项与子项合计不一致")
                }
            }
            if let parentTime = Int(parent.timeSeconds),
               children.allSatisfy({ Int($0.timeSeconds) != nil }) {
                let childTime = children.compactMap { Int($0.timeSeconds) }.reduce(0, +)
                if parentTime != childTime { warnings.append("\(parent.subject)总用时与子项合计不一致") }
            }
        }
        return ExamDerivedMetrics(
            totalQuestions: hasQuestionData ? totals.total : nil,
            correctCount: hasQuestionData ? totals.correct : nil,
            accuracyPercent: hasQuestionData && totals.total > 0 ? Double(totals.correct) * 100 / Double(totals.total) : nil,
            totalTimeSeconds: times.isEmpty ? nil : times.reduce(0, +),
            conflictModules: conflictModules,
            hierarchyWarnings: Array(Set(warnings)).sorted()
        )
    }
}

enum ExamRepository {
    static func save(_ draft: ExamDraft, records: [StoredRecord], context: ModelContext) throws -> String {
        let now = Date()
        let id = draft.id.isEmpty ? "exam_\(Int(now.timeIntervalSince1970 * 1_000))_\(UUID().uuidString.prefix(6))" : draft.id
        let existing = records.first { $0.collection == "exams" && $0.recordID == id }
        var object = draft.original
        let uniqueErrorIDs = Array(draft.linkedErrorIDs).sorted()
        let metrics = draft.metrics
        object["id"] = id
        object["name"] = draft.name
        object["examType"] = draft.examType.rawValue
        object["examDate"] = ExamDraft.dayFormatter.string(from: draft.examDate)
        object["rawReport"] = draft.rawReport
        object["moduleResults"] = draft.moduleResults.map(\.payloadObject)
        object["linkedErrorIds"] = uniqueErrorIDs
        object["updatedAt"] = ISO8601DateFormatter().string(from: now)
        if let score = Double(draft.score), score.isFinite { object["score"] = score } else { object.removeValue(forKey: "score") }
        if let maximumScore = Double(draft.maximumScore), maximumScore.isFinite, maximumScore > 0 { object["maximumScore"] = maximumScore } else { object.removeValue(forKey: "maximumScore") }
        if let total = metrics.totalQuestions { object["totalQuestions"] = total } else { object.removeValue(forKey: "totalQuestions") }
        if let correct = metrics.correctCount { object["correctCount"] = correct } else { object.removeValue(forKey: "correctCount") }
        if let wrong = metrics.wrongCount { object["wrongCount"] = wrong } else { object.removeValue(forKey: "wrongCount") }
        if let accuracy = metrics.accuracyPercent { object["weightedAccuracy"] = accuracy } else { object.removeValue(forKey: "weightedAccuracy") }
        if let seconds = metrics.totalTimeSeconds { object["totalTimeSeconds"] = seconds } else { object.removeValue(forKey: "totalTimeSeconds") }
        object["reviewNote"] = draft.reviewNote
        let payload = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])

        try context.transaction {
            if let existing {
                existing.replacePayload(payload)
                existing.updatedAt = now
            } else {
                context.insert(StoredRecord(collection: "exams", recordID: id, payload: payload, createdAt: now, updatedAt: now))
            }
            let errorRecords = records.filter { $0.collection == "errors" }
            for error in errorRecords {
                var errorObject = error.jsonObject ?? [:]
                let previousExamID = errorObject["sourceExamId"] as? String ?? ""
                let shouldLink = draft.linkedErrorIDs.contains(error.recordID)
                let isLinkedHere = previousExamID == id
                guard shouldLink || isLinkedHere else { continue }
                if shouldLink {
                    if !previousExamID.isEmpty, previousExamID != id,
                       let previousExam = records.first(where: { $0.collection == "exams" && $0.recordID == previousExamID }) {
                        var previousObject = previousExam.jsonObject ?? [:]
                        let priorIDs = Set(previousObject["linkedErrorIds"] as? [String] ?? [])
                        previousObject["linkedErrorIds"] = Array(priorIDs.subtracting(Set([error.recordID]))).sorted()
                        previousObject["updatedAt"] = ISO8601DateFormatter().string(from: now)
                        previousExam.replacePayload(try JSONSerialization.data(withJSONObject: previousObject, options: [.sortedKeys]))
                        previousExam.updatedAt = now
                    }
                    errorObject["sourceExamId"] = id
                    errorObject["reviewSource"] = draft.examType.rawValue
                } else {
                    errorObject.removeValue(forKey: "sourceExamId")
                }
                errorObject["updatedAt"] = ISO8601DateFormatter().string(from: now)
                error.replacePayload(try JSONSerialization.data(withJSONObject: errorObject, options: [.sortedKeys]))
                error.updatedAt = now
            }
            if existing != nil, draft.examType != .mock,
               LibraryMockExamMemory.selectedID(records: records) == id {
                try LibraryMockExamMemory.remember("", records: records, context: context)
            }
        }
        return id
    }

    static func remove(id: String, records: [StoredRecord], context: ModelContext) throws {
        try context.transaction {
            if let exam = records.first(where: { $0.collection == "exams" && $0.recordID == id }) { context.delete(exam) }
            let now = ISO8601DateFormatter().string(from: .now)
            for error in records where error.collection == "errors" {
                var object = error.jsonObject ?? [:]
                guard object["sourceExamId"] as? String == id else { continue }
                object.removeValue(forKey: "sourceExamId")
                object["updatedAt"] = now
                error.replacePayload(try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
                error.updatedAt = .now
            }
            if LibraryMockExamMemory.selectedID(records: records) == id {
                try LibraryMockExamMemory.remember("", records: records, context: context)
            }
        }
    }
}
