import Foundation

public struct DFTOracleCaseObservation: Sendable, Hashable, Codable {
    public var caseID: String
    public var operation: DFTOperation
    public var requestDigest: String
    public var result: DFTResult

    public init(
        caseID: String,
        operation: DFTOperation,
        requestDigest: String,
        result: DFTResult
    ) {
        self.caseID = caseID
        self.operation = operation
        self.requestDigest = requestDigest
        self.result = result
    }
}
