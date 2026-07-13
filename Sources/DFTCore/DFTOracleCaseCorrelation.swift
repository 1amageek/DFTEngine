import Foundation

public struct DFTOracleCaseCorrelation: Sendable, Hashable, Codable {
    public var caseID: String
    public var status: DFTOracleCaseCorrelationStatus
    public var nativeResultDigest: String?
    public var mismatches: [String]

    public init(
        caseID: String,
        status: DFTOracleCaseCorrelationStatus,
        nativeResultDigest: String? = nil,
        mismatches: [String] = []
    ) {
        self.caseID = caseID
        self.status = status
        self.nativeResultDigest = nativeResultDigest
        self.mismatches = mismatches
    }
}
