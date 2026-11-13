import Foundation

public struct MissingCompareGroup: Identifiable, Equatable, Sendable {
    public var id: String { basenameKey }
    public var basenameKey: String
    public var displayName: String
    public var presentAssets: [AssetRecord]
    public var missingFolderPaths: [String]
    public var slots: [AssetRecord?]

    public init(
        basenameKey: String,
        displayName: String,
        presentAssets: [AssetRecord],
        missingFolderPaths: [String],
        slots: [AssetRecord?]
    ) {
        self.basenameKey = basenameKey
        self.displayName = displayName
        self.presentAssets = presentAssets
        self.missingFolderPaths = missingFolderPaths
        self.slots = slots
    }
}
