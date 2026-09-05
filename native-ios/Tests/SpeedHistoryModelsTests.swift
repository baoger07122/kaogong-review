import Foundation

@main
struct SpeedHistoryModelsTests {
    static func main() {
        let calendar = Calendar(identifier: .gregorian)
        let day = Date(timeIntervalSince1970: 1_800_000_000)
        func record(_ id: String, _ minutes: Double, _ name: String, _ correct: Int = 8, _ time: Double = 30) -> SpeedRecord {
            SpeedRecord(id: id, date: day.addingTimeInterval(minutes * 60), name: name, mode: .train,
                totalTime: time, correctCount: correct, totalCount: 10, details: [])
        }
        let records = [
            record("a1", 1, "A"), record("a2", 2, "A"),
            record("b1", 3, "B", 9, 25), record("a3", 4, "A", 10, 20)
        ]
        let groups = SpeedHistoryGrouping.groups(records, calendar: calendar)
        precondition(groups.count == 1)
        precondition(groups[0].blocks.map(\.name) == ["A", "B", "A"])
        precondition(groups[0].blocks[2].records.map(\.id) == ["a2", "a1"])
        precondition(groups[0].blocks[2].totalCount == 20)

        let snapshot = SpeedStatisticsSnapshot(records: records, now: day, calendar: calendar)
        precondition(snapshot.hottest?.name == "A")
        precondition(snapshot.longestFour.first?.name == "A")
        precondition(snapshot.aggregates.first(where: { $0.name == "A" })?.averageTime == 80.0 / 3.0)
        print("PASS consecutive history grouping, newest-first blocks and web statistics aggregation")
    }
}
