import Foundation

public enum DFTDesignDiffReviewState: String, Sendable, Hashable, Codable {
    case proposed
    case approved
    case rejected
    case superseded
}
