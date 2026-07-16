import CircuiteFoundation
import Foundation

public struct DFTDesignDiffChange: Sendable, Hashable, Codable {
    public var changeID: String
    public var domain: DFTDesignDiffDomain
    public var operation: DFTDesignDiffOperation
    public var path: String
    public var fromPath: String?
    public var before: DFTJSONValue?
    public var after: DFTJSONValue?
    public var artifacts: [ArtifactReference]
    public var summary: String

    public init(
        changeID: String,
        domain: DFTDesignDiffDomain,
        operation: DFTDesignDiffOperation,
        path: String,
        fromPath: String? = nil,
        before: DFTJSONValue? = nil,
        after: DFTJSONValue? = nil,
        artifacts: [ArtifactReference] = [],
        summary: String
    ) {
        self.changeID = changeID
        self.domain = domain
        self.operation = operation
        self.path = path
        self.fromPath = fromPath
        self.before = before
        self.after = after
        self.artifacts = artifacts
        self.summary = summary
    }
}
