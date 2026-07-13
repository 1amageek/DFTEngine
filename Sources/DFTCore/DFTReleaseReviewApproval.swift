import Foundation

public struct DFTReleaseReviewApproval: Sendable, Hashable, Codable {
    public var reviewerID: String
    public var decision: Decision
    public var reviewedAt: Date
    public var note: String

    public enum Decision: String, Sendable, Hashable, Codable {
        case approved
        case rejected
    }

    public init(
        reviewerID: String,
        decision: Decision,
        reviewedAt: Date,
        note: String = ""
    ) {
        self.reviewerID = reviewerID
        self.decision = decision
        self.reviewedAt = reviewedAt
        self.note = note
    }
}
