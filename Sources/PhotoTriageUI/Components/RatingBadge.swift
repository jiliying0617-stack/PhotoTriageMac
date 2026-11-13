import PhotoTriageCore
import SwiftUI

struct RatingBadge: View {
    let rating: RatingState

    var body: some View {
        AppStatusPill(rating.title, status: rating.semanticStatus)
    }
}

private extension RatingState {
    var semanticStatus: AppSemanticStatus {
        switch self {
        case .pending:
            return .pending
        case .keep:
            return .keep
        case .reject:
            return .reject
        }
    }
}
