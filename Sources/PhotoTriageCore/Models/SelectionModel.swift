import Foundation

public struct SelectionModel: Equatable, Sendable {
    public var focusedAssetID: UUID?
    public var assetIDs: Set<UUID>
    private var selectionOrder: [UUID]

    public init(
        focusedAssetID: UUID? = nil,
        assetIDs: Set<UUID> = [],
        selectionOrder: [UUID]? = nil
    ) {
        self.focusedAssetID = focusedAssetID
        self.assetIDs = assetIDs
        let uniqueOrder = Self.uniqueIDs(selectionOrder ?? [])
        self.selectionOrder = uniqueOrder.filter { assetIDs.contains($0) }
            + assetIDs.subtracting(uniqueOrder).sorted { $0.uuidString < $1.uuidString }
    }

    public var isEmpty: Bool {
        focusedAssetID == nil && assetIDs.isEmpty
    }

    public mutating func select(_ assetID: UUID?) {
        focusedAssetID = assetID
        assetIDs = []
        selectionOrder = []
    }

    public mutating func toggle(_ assetID: UUID, orderedBy order: (UUID, UUID) -> Bool) {
        if assetIDs.contains(assetID) {
            assetIDs.remove(assetID)
            selectionOrder.removeAll { $0 == assetID }
        } else {
            assetIDs.insert(assetID)
            selectionOrder.append(assetID)
        }
        focusedAssetID = selectionOrder.first ?? assetIDs.sorted(by: order).first
    }

    public mutating func set(_ ids: Set<UUID>, orderedBy order: (UUID, UUID) -> Bool) {
        let retained = selectionOrder.filter { ids.contains($0) }
        let appended = ids.subtracting(retained).sorted(by: order)
        selectionOrder = retained + appended
        assetIDs = ids
        focusedAssetID = selectionOrder.first
    }

    public mutating func setOrdered(_ ids: [UUID]) {
        selectionOrder = Self.uniqueIDs(ids)
        assetIDs = Set(selectionOrder)
        focusedAssetID = selectionOrder.first
    }

    public mutating func clear() {
        focusedAssetID = nil
        assetIDs = []
        selectionOrder = []
    }

    public mutating func normalize(
        existingIDs: Set<UUID>,
        visibleIDs: Set<UUID>? = nil,
        fallbackFocusedID: UUID? = nil
    ) {
        let allowedIDs = visibleIDs.map { existingIDs.intersection($0) } ?? existingIDs
        selectionOrder = selectionOrder.filter { allowedIDs.contains($0) }
        let untrackedIDs = assetIDs
            .intersection(allowedIDs)
            .subtracting(selectionOrder)
            .sorted { $0.uuidString < $1.uuidString }
        selectionOrder.append(contentsOf: untrackedIDs)
        assetIDs = Set(selectionOrder)

        if let focusedAssetID,
           !existingIDs.contains(focusedAssetID) || visibleIDs.map({ !$0.contains(focusedAssetID) }) == true {
            self.focusedAssetID = fallbackFocusedID
        } else if focusedAssetID == nil {
            focusedAssetID = fallbackFocusedID
        }

    }

    public func orderedAssetIDs(by order: (UUID, UUID) -> Bool) -> [UUID] {
        let tracked = selectionOrder.filter { assetIDs.contains($0) }
        let untracked = assetIDs.subtracting(tracked).sorted(by: order)
        return tracked + untracked
    }

    private static func uniqueIDs(_ ids: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
