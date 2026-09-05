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
    var averageTime: Double { practiceCount == 0 ? 0 : totalTime / Double(practiceCount) }
}

struct SpeedDailyAccuracy: Identifiable {
    let date: Date
    let accuracy: Double
    var id: Date { date }
}

struct SpeedStatisticsSnapshot {
    let aggregates: [SpeedTypeAggregate]
    let trend: [SpeedDailyAccuracy]

    var hottest: SpeedTypeAggregate? {
        aggregates.sorted {
            if $0.practiceCount == $1.practiceCount { return $0.totalTime > $1.totalTime }
            return $0.practiceCount > $1.practiceCount
        }.first
    }

    var longestFour: [SpeedTypeAggregate] {
        Array(aggregates.sorted { $0.totalTime > $1.totalTime }.prefix(4))
    }

    init(records: [SpeedRecord], now: Date = .now, calendar: Calendar = .current) {
        aggregates = Dictionary(grouping: records, by: \SpeedRecord.name)
            .map { SpeedTypeAggregate(name: $0.key, records: $0.value) }
        let today = calendar.startOfDay(for: now)
        trend = (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let dayRecords = records.filter { calendar.isDate($0.date, inSameDayAs: date) }
            let total = dayRecords.reduce(0) { $0 + $1.totalCount }
            let correct = dayRecords.reduce(0) { $0 + $1.correctCount }
            return SpeedDailyAccuracy(date: date, accuracy: total == 0 ? 0 : Double(correct) / Double(total))
        }
    }
}
