import CoreGraphics
import Foundation

struct LibraryKnowledgePointTagLayoutSnapshot: Equatable {
    let frames: [CGRect]
    let contentSize: CGSize
}

enum LibraryKnowledgePointTagLayoutPolicy {
    static func layout(
        itemSizes: [CGSize],
        width: CGFloat,
        spacing: CGFloat = 6
    ) -> LibraryKnowledgePointTagLayoutSnapshot {
        guard width > 0, !itemSizes.isEmpty else {
            return LibraryKnowledgePointTagLayoutSnapshot(frames: [], contentSize: CGSize(width: max(0, width), height: 0))
        }

        let gap = max(0, spacing)
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var rowHasItems = false

        for size in itemSizes {
            let itemWidth = min(width, max(0, size.width))
            let itemHeight = max(0, size.height)
            if rowHasItems, x + itemWidth > width + 0.01 {
                y += rowHeight + gap
                x = 0
                rowHeight = 0
                rowHasItems = false
            }

            frames.append(CGRect(x: x, y: y, width: itemWidth, height: itemHeight))
            x += itemWidth + gap
            rowHeight = max(rowHeight, itemHeight)
            rowHasItems = true
        }

        return LibraryKnowledgePointTagLayoutSnapshot(
            frames: frames,
            contentSize: CGSize(width: width, height: y + rowHeight)
        )
    }
}
