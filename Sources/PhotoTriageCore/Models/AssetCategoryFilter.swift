import Foundation

public enum AssetCategoryFilter: Hashable, Sendable {
    case all
    case rating(RatingState)
    case priority(PriorityTag)

    public var title: String {
        switch self {
        case .all:
            return "全部图片"
        case .rating(let rating):
            return rating.title
        case .priority(let tag):
            return tag.displayName
        }
    }
}

public struct AssetCategorySummary: Equatable, Sendable {
    public var totalCount: Int
    public var keepCount: Int
    public var rejectCount: Int
    public var pendingCount: Int
    public var priorityTagSummary: PriorityTagSummary
    public var finderTagColorSummary: FinderTagColorSummary

    public init(
        totalCount: Int = 0,
        keepCount: Int = 0,
        rejectCount: Int = 0,
        pendingCount: Int = 0,
        priorityTagSummary: PriorityTagSummary = PriorityTagSummary(),
        finderTagColorSummary: FinderTagColorSummary = FinderTagColorSummary()
    ) {
        self.totalCount = totalCount
        self.keepCount = keepCount
        self.rejectCount = rejectCount
        self.pendingCount = pendingCount
        self.priorityTagSummary = priorityTagSummary
        self.finderTagColorSummary = finderTagColorSummary
    }

    public func count(for filter: AssetCategoryFilter) -> Int {
        switch filter {
        case .all:
            return totalCount
        case .rating(.keep):
            return keepCount
        case .rating(.reject):
            return rejectCount
        case .rating(.pending):
            return pendingCount
        case .priority(let tag):
            return priorityTagSummary.count(for: tag)
        }
    }
}
