import Foundation

public struct DFTReleaseReviewResumeContract: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var runID: String
    public var sourceStageID: String
    public var resumeStageID: String
    public var designDigest: String
    public var candidateArtifactIDs: [String]
    public var blockerCodes: [String]
    public var requiredReviewItems: [String]
    public var decision: Decision

    public enum Decision: String, Sendable, Hashable, Codable {
        case pending
        case approved
        case rejected
    }

    public init(
        runID: String,
        sourceStageID: String,
        resumeStageID: String,
        designDigest: String,
        candidateArtifactIDs: [String],
        blockerCodes: [String] = [],
        requiredReviewItems: [String] = [],
        decision: Decision = .pending,
        schemaVersion: Int = DFTReleaseReviewResumeContract.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.sourceStageID = sourceStageID
        self.resumeStageID = resumeStageID
        self.designDigest = designDigest
        self.candidateArtifactIDs = candidateArtifactIDs
        self.blockerCodes = blockerCodes
        self.requiredReviewItems = requiredReviewItems
        self.decision = decision
    }
}
