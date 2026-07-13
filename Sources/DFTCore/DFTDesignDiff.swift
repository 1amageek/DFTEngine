import Foundation

public struct DFTDesignDiff: Sendable, Hashable, Codable {
    public var schemaVersion: Int
    public var runID: String
    public var title: String
    public var actor: String
    public var reviewState: DFTDesignDiffReviewState
    public var baseSnapshot: DFTArtifactReference?
    public var proposedSnapshot: DFTArtifactReference?
    public var changes: [DFTDesignDiffChange]
    public var createdAt: Date

    public init(
        schemaVersion: Int = 1,
        runID: String,
        title: String,
        actor: String,
        reviewState: DFTDesignDiffReviewState = .proposed,
        baseSnapshot: DFTArtifactReference? = nil,
        proposedSnapshot: DFTArtifactReference? = nil,
        changes: [DFTDesignDiffChange],
        createdAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.title = title
        self.actor = actor
        self.reviewState = reviewState
        self.baseSnapshot = baseSnapshot
        self.proposedSnapshot = proposedSnapshot
        self.changes = changes
        self.createdAt = createdAt
    }
}
