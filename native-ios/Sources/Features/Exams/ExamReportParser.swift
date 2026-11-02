import Foundation

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
        self.parentSubject = parentSubject ?? ExamModuleCatalog.parentSubject(for: subject)
        self.totalQuestions = totalQuestions
        self.correctCount = correctCount
        self.reportedAccuracy = reportedAccuracy
        self.timeSeconds = timeSeconds
    }

    var isTopLevel: Bool { subject == parentSubject && ExamModuleCatalog.topLevel.contains(subject) }
    var validCounts: (total: Int, correct: Int)? {
        guard let total = Int(totalQuestions), let correct = Int(correctCount),
              total > 0, correct >= 0, correct <= total else { return nil }
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

struct ExamReportMergeResult {
    var lines: [ExamModuleResult]
    var conflicts: [String]
}

enum ExamReportMergePolicy {
    static func merge(
        _ parsedLines: [ExamModuleResult],
        into existingLines: [ExamModuleResult],
        carrying initialConflicts: [String] = []
    ) -> ExamReportMergeResult {
        var lines = existingLines
        var conflictValues = initialConflicts
        for parsed in parsedLines {
            let matches = lines.indices.filter { lines[$0].subject == parsed.subject }
            guard matches.count == 1, let index = matches.first else {
                if matches.isEmpty { lines.append(parsed) }
                else { conflictValues.append(parsed.subject) }
                continue
            }
            var current = lines[index]
            for (old, fresh, label) in [
                (current.totalQuestions, parsed.totalQuestions, "总题数"),
                (current.correctCount, parsed.correctCount, "答对数"),
                (current.reportedAccuracy, parsed.reportedAccuracy, "正确率"),
                (current.timeSeconds, parsed.timeSeconds, "用时")
            ] where !old.isEmpty && !fresh.isEmpty && old != fresh {
                conflictValues.append("\(parsed.subject)\(label)")
            }
            if current.totalQuestions.isEmpty { current.totalQuestions = parsed.totalQuestions }
            if current.correctCount.isEmpty { current.correctCount = parsed.correctCount }
            if current.reportedAccuracy.isEmpty { current.reportedAccuracy = parsed.reportedAccuracy }
            if current.timeSeconds.isEmpty { current.timeSeconds = parsed.timeSeconds }
            lines[index] = current
        }
        return ExamReportMergeResult(lines: lines, conflicts: Array(Set(conflictValues)).sorted())
    }
}

enum ExamModuleCatalog {
    static let placeholderSubject = "选择模块"
    static let topLevel = ["政治理论", "常识判断", "言语理解与表达", "数量关系", "判断推理", "资料分析"]

    static let children: [String: [String]] = [
        "言语理解与表达": ["逻辑填空", "片段阅读", "语句表达"],
        "判断推理": ["图形推理", "定义判断", "类比推理", "逻辑判断"],
        "资料分析": ["文字材料", "表格材料", "图表材料", "综合材料", "单一材料"]
    ]

    private static let aliases: [String: String] = [
        "政治": "政治理论",
        "常识": "常识判断",
        "言语理解": "言语理解与表达",
        "数量": "数量关系",
        "资料": "资料分析"
    ]

    static var selectableSubjects: [String] {
        topLevel.flatMap { [$0] + (children[$0] ?? []) }
    }

    static func canonicalSubject(_ rawValue: String) -> String? {
        let value = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ":：、，,。;；"))
            .replacingOccurrences(of: " ", with: "")
        guard !value.isEmpty else { return nil }
        if selectableSubjects.contains(value) { return value }
        return aliases[value]
    }

    static func parentSubject(for subject: String) -> String {
        for (parent, values) in children where values.contains(subject) { return parent }
        return topLevel.contains(subject) ? subject : subject
    }
}

enum ExamReportParser {
    struct Result {
        var lines: [ExamModuleResult]
        var unparsedLines: [String]
        var duplicateConflicts: [String]
        var warnings: [String]
    }

    private struct Accumulator {
        var subject: String
        var total: Int?
        var correct: Int?
        var accuracy: String?
        var timeSeconds: Int?
        var sourceLines: [String] = []
    }

    private struct MetricsFragment {
        var hasMarker = false
        var total: Int?
        var correct: Int?
        var accuracy: String?
        var timeSeconds: Int?
        var invalidTime: String?
    }

    static func parse(_ rawText: String) -> Result {
        let normalized = rawText
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{3000}", with: " ")
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "％", with: "%")

        var parsed: [ExamModuleResult] = []
        var unparsed: [String] = []
        var conflicts = Set<String>()
        var warnings = Set<String>()
        var current: Accumulator?

        func flushCurrent() {
            guard let value = current else { return }
            current = nil
            guard let total = value.total, let correct = value.correct else {
                unparsed.append(contentsOf: value.sourceLines)
                return
            }
            if correct > total || total <= 0 {
                warnings.insert("\(value.subject)：题数与答对数不合理，请核对")
            }
            let row = ExamModuleResult(
                subject: value.subject,
                totalQuestions: String(total),
                correctCount: String(correct),
                reportedAccuracy: value.accuracy ?? "",
                timeSeconds: value.timeSeconds.map(String.init) ?? ""
            )
            guard let previousIndex = parsed.firstIndex(where: { $0.subject == row.subject }) else {
                parsed.append(row)
                return
            }
            var previous = parsed[previousIndex]
            let hasConflictingField = [
                (previous.totalQuestions, row.totalQuestions),
                (previous.correctCount, row.correctCount),
                (previous.reportedAccuracy, row.reportedAccuracy),
                (previous.timeSeconds, row.timeSeconds)
            ].contains { pair in !pair.0.isEmpty && !pair.1.isEmpty && pair.0 != pair.1 }
            if hasConflictingField {
                conflicts.insert(row.subject)
                parsed.append(row)
                return
            }
            if previous.totalQuestions.isEmpty { previous.totalQuestions = row.totalQuestions }
            if previous.correctCount.isEmpty { previous.correctCount = row.correctCount }
            if previous.reportedAccuracy.isEmpty { previous.reportedAccuracy = row.reportedAccuracy }
            if previous.timeSeconds.isEmpty { previous.timeSeconds = row.timeSeconds }
            parsed[previousIndex] = previous
        }

        func apply(_ fragment: MetricsFragment, sourceLine: String) {
            guard var value = current else { return }
            if let total = fragment.total { value.total = total }
            if let correct = fragment.correct { value.correct = correct }
            if let accuracy = fragment.accuracy { value.accuracy = accuracy }
            if let timeSeconds = fragment.timeSeconds { value.timeSeconds = timeSeconds }
            if let invalidTime = fragment.invalidTime {
                warnings.insert("用时无法识别：\(invalidTime)")
                unparsed.append(sourceLine)
            }
            current = value
        }

        for sourceLine in joinSplitMetricLabels(normalized) {
            let line = stripDecoration(sourceLine)
            guard !line.isEmpty else { continue }

            if let range = line.range(of: "共") {
                let prefix = String(line[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !prefix.isEmpty {
                    guard let subject = ExamModuleCatalog.canonicalSubject(prefix) else {
                        flushCurrent()
                        unparsed.append(line)
                        continue
                    }
                    flushCurrent()
                    current = Accumulator(subject: subject, sourceLines: [line])
                    apply(parseMetrics(String(line[range.lowerBound...])), sourceLine: line)
                    continue
                }
            }

            if let subject = ExamModuleCatalog.canonicalSubject(line) {
                flushCurrent()
                current = Accumulator(subject: subject, sourceLines: [line])
                continue
            }

            let fragment = parseMetrics(line)
            if fragment.hasMarker {
                guard current != nil else {
                    unparsed.append(line)
                    continue
                }
                if fragment.total == nil, fragment.correct == nil, fragment.accuracy == nil,
                   fragment.timeSeconds == nil, fragment.invalidTime == nil {
                    unparsed.append(line)
                    continue
                }
                current?.sourceLines.append(line)
                apply(fragment, sourceLine: line)
                continue
            }

            flushCurrent()
            unparsed.append(line)
        }
        flushCurrent()

        return Result(
            lines: parsed,
            unparsedLines: unparsed,
            duplicateConflicts: conflicts.sorted(),
            warnings: warnings.sorted()
        )
    }

    private static func stripDecoration(_ source: String) -> String {
        var line = source.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = line.first, "•·*-–—".contains(first) {
            line.removeFirst()
            line = line.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return line
    }

    private static func joinSplitMetricLabels(_ text: String) -> [String] {
        let sourceLines = text.components(separatedBy: .newlines)
        var merged: [String] = []
        var index = 0
        while index < sourceLines.count {
            var line = stripDecoration(sourceLines[index])
            index += 1
            while endsWithMetricLabel(line), index < sourceLines.count {
                let next = stripDecoration(sourceLines[index])
                let valueStart = next.range(of: #"^[0-9０-９]"#, options: .regularExpression) != nil
                guard valueStart else { break }
                line += next
                index += 1
            }
            merged.append(line)
        }
        return merged
    }

    private static func endsWithMetricLabel(_ line: String) -> Bool {
        line.range(of: #"(?:共|答对|正确率|用时)\s*[:：]?\s*$"#, options: .regularExpression) != nil
    }

    private static func parseMetrics(_ line: String) -> MetricsFragment {
        var value = MetricsFragment()
        value.hasMarker = ["共", "答对", "正确率", "用时"].contains { line.contains($0) }
        guard value.hasMarker else { return value }

        value.total = firstInteger(pattern: #"共\s*(\d+)\s*(?:道|题)?"#, in: line)
        value.correct = firstInteger(pattern: #"答对\s*(\d+)\s*(?:道|题)?"#, in: line)
        value.accuracy = firstCapture(pattern: #"正确率\s*:?\s*(\d+(?:\.\d+)?)\s*%"#, in: line)
        if let rawTime = firstCapture(pattern: #"用时\s*:?\s*(.+?)\s*$"#, in: line) {
            let cleanTime = rawTime.trimmingCharacters(in: CharacterSet(charactersIn: " \t,;；。"))
            if let seconds = parseTime(cleanTime) {
                value.timeSeconds = seconds
            } else {
                value.invalidTime = cleanTime
            }
        }
        return value
    }

    private static func firstInteger(pattern: String, in value: String) -> Int? {
        guard let capture = firstCapture(pattern: pattern, in: value) else { return nil }
        return Int(capture)
    }

    private static func firstCapture(pattern: String, in value: String) -> String? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: value) else { return nil }
        return String(value[range])
    }

    static func parseTime(_ value: String) -> Int? {
        let clean = value
            .replacingOccurrences(of: "：", with: ":")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if clean.contains(":") {
            let parts = clean.split(separator: ":", omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            guard (parts.count == 2 || parts.count == 3), parts.allSatisfy({ !$0.isEmpty }) else { return nil }
            let values = parts.compactMap(Int.init)
            guard values.count == parts.count, values.allSatisfy({ $0 >= 0 }) else { return nil }
            if values.count == 2 {
                let (minutes, overflow) = values[0].multipliedReportingOverflow(by: 60)
                let (seconds, additionOverflow) = minutes.addingReportingOverflow(values[1])
                guard values[1] < 60, !overflow, !additionOverflow else { return nil }
                return seconds
            }
            let (hours, hourOverflow) = values[0].multipliedReportingOverflow(by: 3_600)
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
            let multiplier = ["小时", "时"].contains(unit) ? 3_600 : (["分钟", "分"].contains(unit) ? 60 : 1)
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
        let parents = topLevelGrouped.compactMap { _, values -> ExamModuleResult? in
            guard values.count == 1 else { return nil }
            return values[0]
        }
        let countRows = parents.compactMap { row -> (Int, Int)? in
            guard let values = row.validCounts else { return nil }
            return (values.total, values.correct)
        }
        let totals = countRows.reduce(into: (total: 0, correct: 0)) { $0.total += $1.0; $0.correct += $1.1 }
        let times = parents.compactMap { Int($0.timeSeconds) }.filter { $0 >= 0 }
        var warnings: [String] = []
        for parent in parents {
            let children = lines.filter { $0.parentSubject == parent.subject && !$0.isTopLevel }
            guard !children.isEmpty,
                  !children.contains(where: { conflictKeys.contains("\($0.parentSubject)\u{1F}\($0.subject)") }) else { continue }
            if let parentCounts = parent.validCounts, children.allSatisfy({ $0.validCounts != nil }) {
                let childCounts = children.compactMap(\.validCounts)
                if parentCounts.total != childCounts.reduce(0, { $0 + $1.total })
                    || parentCounts.correct != childCounts.reduce(0, { $0 + $1.correct }) {
                    warnings.append("\(parent.subject)总项与子项合计不一致")
                }
            }
            if let parentTime = Int(parent.timeSeconds), children.allSatisfy({ Int($0.timeSeconds) != nil }) {
                let childTime = children.compactMap { Int($0.timeSeconds) }.reduce(0, +)
                if parentTime != childTime { warnings.append("\(parent.subject)总用时与子项合计不一致") }
            }
        }
        let hasQuestionData = !countRows.isEmpty
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
