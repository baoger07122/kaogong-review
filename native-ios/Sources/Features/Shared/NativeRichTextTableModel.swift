import Foundation

struct RichTextTable: Codable, Equatable, Identifiable {
    enum Presentation: String, Codable { case flow }
    enum StructureAction { case addRow, removeRow, addColumn, removeColumn, moveUp, moveDown }

    struct Cell: Equatable {
        let row: Int
        let column: Int
    }

    static let maximumRows = 16
    static let maximumColumns = 8
    static let maximumCellBytes = 512

    var id = UUID()
    var cells: [[String]] = Array(repeating: Array(repeating: "", count: 2), count: 2)
    var cellBoldRanges: [NativeRichTextPastedBoldRange]? = nil

    var presentation: Presentation? = nil

    static func flowchart() -> RichTextTable {
        RichTextTable(presentation: .flow)
    }

    var isFlowchart: Bool { presentation == .flow }
    var rowCount: Int { cells.count }
    var columnCount: Int { cells.first?.count ?? 0 }

    func contains(_ cell: Cell) -> Bool {
        cells.indices.contains(cell.row) && cells[cell.row].indices.contains(cell.column)
    }

    func plainText() -> String {
        if isFlowchart {
            return cells.enumerated().map { index, row in
                let title = row.first.flatMap { $0.isEmpty ? nil : $0 } ?? "步骤 \(index + 1)"
                let detail = row.dropFirst().first ?? ""
                return detail.isEmpty ? title : title + "\n" + detail
            }.joined(separator: "\n\n")
        }
        return cells.map { $0.joined(separator: "\t") }.joined(separator: "\n")
    }

    mutating func replaceText(at cell: Cell, with text: String) {
        guard contains(cell), cells[cell.row][cell.column] != text else { return }
        let old = cells[cell.row][cell.column] as NSString
        let new = text as NSString
        var prefix = 0
        let common = min(old.length, new.length)
        while prefix < common, old.character(at: prefix) == new.character(at: prefix) { prefix += 1 }
        var suffix = 0
        while suffix < common - prefix,
              old.character(at: old.length - suffix - 1) == new.character(at: new.length - suffix - 1) { suffix += 1 }
        cells[cell.row][cell.column] = text
        cellBoldRanges = cellBoldRanges?.compactMap { range in
            guard range.row == cell.row, range.column == cell.column else { return range }
            if range.location <= prefix, range.length <= prefix - range.location { return range }
            if range.location >= old.length - suffix {
                return NativeRichTextPastedBoldRange(
                    row: range.row, column: range.column,
                    location: range.location + new.length - old.length, length: range.length
                )
            }
            return nil
        }
        normalizeBoldRanges()
    }

    func canApply(_ action: StructureAction, at cell: Cell) -> Bool {
        guard contains(cell) else { return false }
        switch action {
        case .addRow: return rowCount < Self.maximumRows
        case .removeRow: return rowCount > 1
        case .addColumn: return !isFlowchart && columnCount < Self.maximumColumns
        case .removeColumn: return !isFlowchart && columnCount > 1
        case .moveUp: return isFlowchart && cell.row > 0
        case .moveDown: return isFlowchart && cell.row + 1 < rowCount
        }
    }

    mutating func apply(_ action: StructureAction, at cell: Cell) -> Cell? {
        guard canApply(action, at: cell) else { return nil }
        var rows = cells.indices.map(Optional.some)
        var columns = (0..<columnCount).map(Optional.some)
        var row = cell.row
        var column = cell.column
        switch action {
        case .addRow: row += 1; rows.insert(nil, at: row)
        case .removeRow: rows.remove(at: row); row = min(row, rows.count - 1)
        case .addColumn: column += 1; columns.insert(nil, at: column)
        case .removeColumn: columns.remove(at: column); column = min(column, columns.count - 1)
        case .moveUp: row -= 1; rows.swapAt(cell.row, row)
        case .moveDown: row += 1; rows.swapAt(cell.row, row)
        }

        let previousCells = cells
        cells = rows.map { oldRow in
            columns.map { oldColumn in
                guard let oldRow, let oldColumn, previousCells[oldRow].indices.contains(oldColumn) else { return "" }
                return previousCells[oldRow][oldColumn]
            }
        }
        cellBoldRanges = cellBoldRanges?.compactMap { range in
            guard let row = rows.firstIndex(of: range.row),
                  let column = columns.firstIndex(of: range.column) else { return nil }
            return NativeRichTextPastedBoldRange(row: row, column: column, location: range.location, length: range.length)
        }
        return Cell(row: row, column: column)
    }

    mutating func normalizeBoldRanges() {
        let source = cellBoldRanges ?? []
        cellBoldRanges = source.filter { range in
            guard cells.indices.contains(range.row), cells[range.row].indices.contains(range.column), range.length > 0 else { return false }
            let cell = cells[range.row][range.column] as NSString
            guard range.location >= 0,
                  range.location <= cell.length,
                  range.length <= cell.length - range.location else { return false }
            let end = range.location + range.length
            if range.location > 0, range.location < cell.length,
               (0xDC00...0xDFFF).contains(cell.character(at: range.location)),
               (0xD800...0xDBFF).contains(cell.character(at: range.location - 1)) { return false }
            if end > 0, end < cell.length,
               (0xDC00...0xDFFF).contains(cell.character(at: end)),
               (0xD800...0xDBFF).contains(cell.character(at: end - 1)) { return false }
            return true
        }
    }
}
