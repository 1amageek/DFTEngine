import Foundation

public struct DFTOracleCorrelationResult: Sendable, Hashable, Codable {
    public var corpusID: String
    public var corpusRevision: String
    public var processID: String
    public var pdkDigest: String
    public var corpusDigest: String
    public var oracleEvidenceDigest: String
    public var status: DFTOracleCorrelationStatus
    public var totalCaseCount: Int
    public var passedCaseCount: Int
    public var cases: [DFTOracleCaseCorrelation]
    public var diagnostics: [String]

    public init(
        corpusID: String,
        corpusRevision: String,
        processID: String,
        pdkDigest: String,
        corpusDigest: String,
        oracleEvidenceDigest: String,
        status: DFTOracleCorrelationStatus,
        totalCaseCount: Int,
        passedCaseCount: Int,
        cases: [DFTOracleCaseCorrelation],
        diagnostics: [String] = []
    ) {
        self.corpusID = corpusID
        self.corpusRevision = corpusRevision
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.corpusDigest = corpusDigest
        self.oracleEvidenceDigest = oracleEvidenceDigest
        self.status = status
        self.totalCaseCount = totalCaseCount
        self.passedCaseCount = passedCaseCount
        self.cases = cases.sorted { $0.caseID < $1.caseID }
        self.diagnostics = diagnostics
    }
}
