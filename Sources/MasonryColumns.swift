import Foundation

// Arrange data first; rendering and scrolling remain in SwiftUI's own stacks.
struct MasonryColumns {
    struct Entry: Identifiable {
        let item: WallItem
        let number: Int
        let aspectRatio: Double
        var id: URL { item.id }
    }

    static func make(items: [WallItem], count: Int, columnWidth: Double, spacing: Double) -> [[Entry]] {
        guard count > 0 else { return [] }
        var columns = Array(repeating: [Entry](), count: count)
        var heights = Array(repeating: 0.0, count: count)
        for (index, item) in items.enumerated() {
            let column = heights.indices.min { heights[$0] < heights[$1] } ?? 0
            let aspectRatio = item.dimensions.map { min(2.6, max(0.4, Double($0.width) / Double($0.height))) } ?? 4.0 / 3.0
            columns[column].append(Entry(item: item, number: index + 1, aspectRatio: aspectRatio))
            heights[column] += columnWidth / aspectRatio + spacing
        }
        return columns
    }
}
