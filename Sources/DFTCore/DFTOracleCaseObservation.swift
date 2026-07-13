import Foundation
import XcircuitePackage

public struct DFTOracleCaseObservation: Sendable, Hashable, Codable {
    public var caseID: String
    public var operation: DFTOperation
    public var requestDigest: String
    public var result: XcircuiteEngineResultEnvelope<DFTPayload>

    public init(
        caseID: String,
        operation: DFTOperation,
        requestDigest: String,
        result: XcircuiteEngineResultEnvelope<DFTPayload>
    ) {
        self.caseID = caseID
        self.operation = operation
        self.requestDigest = requestDigest
        self.result = result
    }
}
