import Foundation

public struct ExportPlanner: ExportPlanning {
    public init() {}

    public func buildExportBuckets(
        from assets: [AssetRecord],
        includePending: Bool
    ) -> [RatingState: [AssetRecord]] {
        var buckets: [RatingState: [AssetRecord]] = [
            .keep: [],
            .reject: [],
        ]

        if includePending {
            buckets[.pending] = []
        }

        for asset in assets {
            switch asset.ratingState {
            case .pending where includePending:
                buckets[.pending, default: []].append(asset)
            case .keep:
                buckets[.keep, default: []].append(asset)
            case .reject:
                buckets[.reject, default: []].append(asset)
            default:
                break
            }
        }

        return buckets
    }
}
