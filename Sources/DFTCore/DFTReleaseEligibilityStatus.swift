import Foundation

public enum DFTReleaseEligibilityStatus: String, Sendable, Hashable, Codable {
    case eligible
    case needsReview
    case blocked
}
