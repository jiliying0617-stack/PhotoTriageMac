import Foundation

public struct FinderTagColorSummary: Equatable, Sendable {
    public var counts: [FinderTagColor: Int]

    public init(counts: [FinderTagColor: Int] = [:]) {
        self.counts = counts
    }

    public init(assets: [AssetRecord]) {
        var counts: [FinderTagColor: Int] = [:]
        for asset in assets {
            for color in Set(asset.finderTags.map(\.color)) {
                counts[color, default: 0] += 1
            }
        }
        self.counts = counts
    }

    public func count(for color: FinderTagColor) -> Int {
        counts[color, default: 0]
    }
}
