import Foundation
import XcircuitePackage

public struct DFTOracleCorpusCase: Sendable, Hashable, Codable {
    public var caseID: String
    public var operation: DFTOperation
    public var requestDigest: String
    public var expectation: DFTOracleCaseExpectation
    public var oracleArtifact: XcircuiteFileReference

    public init(
        caseID: String,
        operation: DFTOperation,
        requestDigest: String,
        expectation: DFTOracleCaseExpectation,
        oracleArtifact: XcircuiteFileReference
    ) {
        self.caseID = caseID
        self.operation = operation
        self.requestDigest = requestDigest
        self.expectation = expectation
        self.oracleArtifact = oracleArtifact
    }
}
