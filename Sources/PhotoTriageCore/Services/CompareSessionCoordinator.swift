import Foundation

public struct CompareSessionCoordinator: Sendable {
    public init() {}

    public func makeSession(selectionIDs: [UUID], focusedAssetID: UUID? = nil) -> CompareSessionState {
        CompareSessionState(
            selectionIDs: selectionIDs,
            temporaryOverlaySlot: nil,
            focusedAssetID: focusedAssetID,
            overlayAssetID: nil
        )
    }

    public func focusedAssetID(in session: CompareSessionState) -> UUID? {
        if let focusedAssetID = session.focusedAssetID,
           session.selectionIDs.contains(focusedAssetID) {
            return focusedAssetID
        }

        return session.selectionIDs.first
    }

    public func overlayAssetID(in session: CompareSessionState) -> UUID? {
        guard let overlayAssetID = session.overlayAssetID,
              session.selectionIDs.contains(overlayAssetID),
              overlayAssetID != focusedAssetID(in: session) else {
            return nil
        }

        return overlayAssetID
    }

    public func overlayCandidateIDs(in session: CompareSessionState) -> [UUID] {
        session.selectionIDs.filter { $0 != focusedAssetID(in: session) }
    }

    public func focus(_ assetID: UUID, in session: inout CompareSessionState) {
        guard session.selectionIDs.contains(assetID) else { return }
        session.focusedAssetID = assetID
        session.overlayAssetID = nil
        session.temporaryOverlaySlot = nil
        normalize(&session)
    }

    public func showOverview(in session: inout CompareSessionState) {
        session.focusedAssetID = nil
        session.overlayAssetID = nil
        session.temporaryOverlaySlot = nil
        normalize(&session)
    }

    public func toggleOverlay(slot: Int, in session: inout CompareSessionState) -> UUID? {
        let zeroBased = slot - 1
        guard session.selectionIDs.indices.contains(zeroBased) else { return nil }

        let assetID = session.selectionIDs[zeroBased]
        guard assetID != focusedAssetID(in: session) else { return nil }

        session.overlayAssetID = session.overlayAssetID == assetID ? nil : assetID
        session.temporaryOverlaySlot = nil
        normalize(&session)
        return assetID
    }

    public func setBaseOverlay(slot: Int, in session: inout CompareSessionState) -> (baseID: UUID, overlayID: UUID)? {
        let zeroBased = slot - 1
        guard session.selectionIDs.indices.contains(zeroBased),
              let baseAssetID = session.selectionIDs.first else { return nil }

        let overlayAssetID = session.selectionIDs[zeroBased]
        session.focusedAssetID = baseAssetID
        session.overlayAssetID = overlayAssetID == baseAssetID ? nil : overlayAssetID
        session.temporaryOverlaySlot = nil
        normalize(&session)
        return (baseAssetID, overlayAssetID)
    }

    public func cyclicOverlayAssetID(forAssetAt index: Int, in session: CompareSessionState) -> UUID? {
        guard session.selectionIDs.count >= 2,
              session.selectionIDs.indices.contains(index) else { return nil }
        let overlayIndex = index == session.selectionIDs.count - 1 ? 0 : index + 1
        return session.selectionIDs[overlayIndex]
    }

    public func beginTemporaryOverlay(slot: Int, in session: inout CompareSessionState) -> Int? {
        let zeroBased = slot - 1
        guard overlayCandidateIDs(in: session).indices.contains(zeroBased) else { return nil }
        session.temporaryOverlaySlot = zeroBased
        return zeroBased
    }

    public func endTemporaryOverlay(in session: inout CompareSessionState) {
        session.temporaryOverlaySlot = nil
    }

    public func toggleTemporaryOverlay(in session: inout CompareSessionState) -> Int? {
        let candidates = overlayCandidateIDs(in: session)
        guard !candidates.isEmpty else { return nil }

        if session.temporaryOverlaySlot == nil {
            session.temporaryOverlaySlot = 0
            return 0
        } else {
            session.temporaryOverlaySlot = nil
            return nil
        }
    }

    public func removeSelectionIDs(_ removedIDs: Set<UUID>, from session: inout CompareSessionState) {
        session.selectionIDs.removeAll { removedIDs.contains($0) }
        normalize(&session)
    }

    public func normalize(_ session: inout CompareSessionState) {
        if let focusedAssetID = session.focusedAssetID,
           !session.selectionIDs.contains(focusedAssetID) {
            session.focusedAssetID = session.selectionIDs.first
        }

        if let overlayAssetID = session.overlayAssetID,
           !session.selectionIDs.contains(overlayAssetID) || overlayAssetID == focusedAssetID(in: session) {
            session.overlayAssetID = nil
        }

        let overlayCandidateCount = overlayCandidateIDs(in: session).count
        if let temporaryOverlaySlot = session.temporaryOverlaySlot,
           temporaryOverlaySlot >= overlayCandidateCount {
            session.temporaryOverlaySlot = nil
        }
    }
}
