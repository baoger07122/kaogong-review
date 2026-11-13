import Foundation

struct RichTextTable: Codable, Equatable, Identifiable {
    var id = UUID()
    var cells: [[String]] = Array(repeating: Array(repeating: "", count: 2), count: 2)
    var cellBoldRanges: [NativeRichTextPastedBoldRange]? = nil

    var rowCount: Int { cells.count }
    var columnCount: Int { cells.first?.count ?? 0 }

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
