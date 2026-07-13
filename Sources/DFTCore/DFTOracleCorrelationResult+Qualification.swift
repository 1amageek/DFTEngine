import Foundation
import XcircuitePackage

public extension DFTOracleCorrelationResult {
    func makeQualificationEvidence(
        evidenceID: String,
        engineID: String,
        implementationID: String,
        approvedBy: String?,
        artifacts: [XcircuiteFileReference] = []
    ) throws -> DFTQualificationEvidence {
        guard status == .correlated else {
            throw DFTQualificationError.invalidEvidence(
                "oracle correlation status " + status.rawValue + " cannot be promoted"
            )
        }
        return DFTQualificationEvidence(
            evidenceID: evidenceID,
            engineID: engineID,
            implementationID: implementationID,
            processID: processID,
            pdkDigest: pdkDigest,
            corpusRevision: corpusRevision,
            totalCaseCount: totalCaseCount,
            passedCaseCount: passedCaseCount,
            oracleEvidenceDigest: oracleEvidenceDigest,
            approvedBy: approvedBy,
            artifacts: artifacts
        )
    }
}
