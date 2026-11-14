import CoreGraphics
import Foundation

@main
enum LibraryKnowledgePointTagLayoutBehavior {
    static func main() {
        verifyLeftAlignmentAndFixedSpacing()
        verifyWrappingAndMeasuredHeightShareFrames()
        verifyOverwideItemStaysInsideItsContainer()
    }

    private static func verifyLeftAlignmentAndFixedSpacing() {
        let layout = LibraryKnowledgePointTagLayoutPolicy.layout(
            itemSizes: [CGSize(width: 80, height: 24), CGSize(width: 90, height: 24)],
            width: 240
        )
        precondition(layout.frames[0].minX == 0, "the first tag must align to the leading edge")
        precondition(layout.frames[1].minX - layout.frames[0].maxX == 6, "tags must use the same fixed 6 pt gap")
        precondition(layout.contentSize.height == layout.frames[1].maxY, "measured height must end at the final row")
    }

    private static func verifyWrappingAndMeasuredHeightShareFrames() {
        let layout = LibraryKnowledgePointTagLayoutPolicy.layout(
            itemSizes: [CGSize(width: 90, height: 24), CGSize(width: 104, height: 30), CGSize(width: 30, height: 20)],
            width: 180
        )
        precondition(layout.frames[0].minY == 0, "the first row must start at the top edge")
        precondition(layout.frames[1].minY == 30, "the second tag must move to a new row when it does not fit")
        precondition(layout.frames[2].minY == layout.frames[1].minY, "the following tag must share the available second row")
        precondition(layout.frames[2].minY - layout.frames[0].maxY == 6, "row spacing must stay fixed at 6 pt")
        precondition(layout.contentSize.height == (layout.frames.map(\.maxY).max() ?? 0), "measured height must match the laid out rows")
        precondition(layout.frames.allSatisfy { $0.minX >= 0 && $0.maxX <= 180 }, "tag frames must stay within the available width")
    }

    private static func verifyOverwideItemStaysInsideItsContainer() {
        let layout = LibraryKnowledgePointTagLayoutPolicy.layout(
            itemSizes: [CGSize(width: 240, height: 48)],
            width: 160
        )
        precondition(layout.frames[0].width == 160, "an overwide label must wrap inside the collection width")
        precondition(layout.contentSize.height == 48, "a wrapped label's measured height must come from its item frame")
    }
}
