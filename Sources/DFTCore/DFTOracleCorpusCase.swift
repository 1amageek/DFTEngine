import Foundation

public struct DFTOracleCorpusCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var operation: DFTOperation
    public var requestDigest: String
    public var expectation: DFTOracleCaseExpectation
    public var oracleArtifact: DFTArtifactReference

    public init(
        caseID: String,
        operation: DFTOperation,
        requestDigest: String,
        expectation: DFTOracleCaseExpectation,
        oracleArtifact: DFTArtifactReference
    ) {
        self.caseID = caseID
        self.operation = operation
        self.requestDigest = requestDigest
        self.expectation = expectation
        self.oracleArtifact = oracleArtifact
    }
}
