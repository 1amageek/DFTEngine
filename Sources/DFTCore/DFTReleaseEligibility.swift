import Foundation

public struct DFTReleaseEligibility: Sendable, Hashable, Codable {
    public var runID: String
    public var status: DFTReleaseEligibilityStatus
    public var requiredArtifactIDs: [String]
    public var downstreamDomains: [DFTReleaseDownstreamEvidence.Domain]
    public var reviewApproval: DFTReleaseReviewApproval?
    public var reviewResumeContract: DFTReleaseReviewResumeContract
    public var diagnostics: [String]

    public init(
        runID: String,
        status: DFTReleaseEligibilityStatus,
        requiredArtifactIDs: [String],
        downstreamDomains: [DFTReleaseDownstreamEvidence.Domain],
        reviewApproval: DFTReleaseReviewApproval?,
        reviewResumeContract: DFTReleaseReviewResumeContract,
        diagnostics: [String] = []
    ) {
        self.runID = runID
        self.status = status
        self.requiredArtifactIDs = requiredArtifactIDs
        self.downstreamDomains = downstreamDomains
        self.reviewApproval = reviewApproval
        self.reviewResumeContract = reviewResumeContract
        self.diagnostics = diagnostics
    }
}
