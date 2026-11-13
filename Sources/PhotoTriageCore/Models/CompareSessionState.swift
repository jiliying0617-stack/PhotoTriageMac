import Foundation

public struct CompareSessionState: Equatable, Sendable {
    public var selectionIDs: [UUID]
    /// Nonempty for folder-group comparison. Empty folder slots remain visible.
    public var folderPaths: [String]
    public var temporaryOverlaySlot: Int?
    public var focusedAssetID: UUID?
    public var overlayAssetID: UUID?

    public init(
        selectionIDs: [UUID] = [],
        folderPaths: [String] = [],
        temporaryOverlaySlot: Int? = nil,
        focusedAssetID: UUID? = nil,
        overlayAssetID: UUID? = nil
    ) {
        self.selectionIDs = selectionIDs
        self.folderPaths = folderPaths
        self.temporaryOverlaySlot = temporaryOverlaySlot
        self.focusedAssetID = focusedAssetID
        self.overlayAssetID = overlayAssetID
    }
}
