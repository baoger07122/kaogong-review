import Foundation

struct SpeedHistoryDayGroup: Identifiable {
    let date: Date
    let blocks: [SpeedHistoryBlock]
    var id: Date { date }
}

struct SpeedHistoryBlock: Identifiable {
    let id: String
    let name: String
    let records: [SpeedRecord]

    var totalCount: Int { records.reduce(0) { $0 + $1.totalCount } }
    var correctCount: Int { records.reduce(0) { $0 + $1.correctCount } }
    var totalTime: Double { records.reduce(0) { $0 + $1.totalTime } }
    var averageTime: Double { records.isEmpty ? 0 : totalTime / Double(records.count) }
    var accuracy: Double { totalCount == 0 ? 0 : Double(correctCount) / Double(totalCount) }
}

enum SpeedHistoryGrouping {
    static func groups(_ records: [SpeedRecord], calendar: Calendar = .current) -> [SpeedHistoryDayGroup] {
        let byDay = Dictionary(grouping: records) { calendar.startOfDay(for: $0.date) }
        return byDay.keys.sorted(by: >).map { day in
            let chronological = (byDay[day] ?? []).sorted { $0.date < $1.date }
            var runs: [(name: String, records: [SpeedRecord])] = []
            for record in chronological {
                if runs.last?.name == record.name {
                    runs[runs.count - 1].records.append(record)
                } else {
                    runs.append((record.name, [record]))
                }
            }
            let blocks = runs.reversed().enumerated().map { index, run in
                let newestFirst = run.records.reversed()
                let records = Array(newestFirst)
                return SpeedHistoryBlock(
                    id: "\(day.timeIntervalSince1970)-\(index)-\(records.first?.id ?? run.name)",
                    name: run.name,
                    records: records
                )
            }
            return SpeedHistoryDayGroup(date: day, blocks: blocks)
        }
    }
}

struct SpeedTypeAggregate: Identifiable {
    let name: String
    let records: [SpeedRecord]
    var id: String { name }
    var practiceCount: Int { records.count }
    var totalCount: Int { records.reduce(0) { $0 + $1.totalCount } }
    var correctCount: Int { records.reduce(0) { $0 + $1.correctCount } }
    var totalTime: Double { records.reduce(0) { $0 + $1.totalTime } }
    var accuracy: Double { totalCount == 0 ? 0 : Double(correctCount) / Double(totalCount) }
    var averageTime: Double { totalCount == 0 ? 0 : totalTime / Double(totalCount) * 10 }
}

struct SpeedDailyStatistics: Identifiable {
    let date: Date
    let questionCount: Int
    let accuracy: Double?
    let secondsPerTenQuestions: Double?
    var id: Date { date }
}

struct SpeedStatisticsSnapshot {
    let typeOptions: [String]
    let selectedAggregate: SpeedTypeAggregate?
    let crossTypeAggregates: [SpeedTypeAggregate]
    let trend: [SpeedDailyStatistics]

    var longestFour: [SpeedTypeAggregate] {
        Array(crossTypeAggregates.sorted {
            if $0.averageTime == $1.averageTime { return $0.totalTime > $1.totalTime }
            return $0.averageTime > $1.averageTime
        }.prefix(4))
    }

    init(
        records: [SpeedRecord],
        selectedType: String = "全部",
        dayCount: Int = 7,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        let names = Set(records.map { Self.displayType(for: $0.name) })
        typeOptions = ["全部"] + names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let selectedRecords = records.filter { selectedType == "全部" || Self.displayType(for: $0.name) == selectedType }
        selectedAggregate = selectedRecords.isEmpty
            ? nil
            : SpeedTypeAggregate(name: selectedType == "全部" ? "全部" : selectedType, records: selectedRecords)
        crossTypeAggregates = Dictionary(grouping: records, by: { Self.displayType(for: $0.name) })
            .map { SpeedTypeAggregate(name: $0.key, records: $0.value) }
        let today = calendar.startOfDay(for: now)
        trend = (0..<max(1, dayCount)).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayRecords = selectedRecords.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let total = dayRecords.reduce(0) { $0 + $1.totalCount }
            let correct = dayRecords.reduce(0) { $0 + $1.correctCount }
            let totalTime = dayRecords.reduce(0) { $0 + $1.totalTime }
            return SpeedDailyStatistics(
                date: date,
                questionCount: total,
                accuracy: total == 0 ? nil : Double(correct) / Double(total),
                secondsPerTenQuestions: total == 0 ? nil : totalTime / Double(total) * 10
            )
        }
    }

    static func displayType(for name: String) -> String {
        name.hasPrefix("自定义练习") ? "自定义练习" : name
    }
}
