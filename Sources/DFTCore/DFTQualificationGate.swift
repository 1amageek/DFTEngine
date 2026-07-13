import Foundation
import CircuiteFoundation
import XcircuitePackage

public struct DFTQualificationGate: Sendable {
    public init() {}

    public func evaluate(
        _ evidence: DFTQualificationEvidence,
        expectedProcessID: String,
        expectedPDKDigest: String
    ) throws -> DFTQualificationProvenance {
        guard evidence.schemaVersion == DFTQualificationEvidence.currentSchemaVersion else {
            throw DFTQualificationError.invalidEvidence("unsupported schema version \(evidence.schemaVersion)")
        }
        guard !evidence.evidenceID.isEmpty,
              !evidence.engineID.isEmpty,
              !evidence.implementationID.isEmpty,
              !evidence.processID.isEmpty,
              !evidence.corpusRevision.isEmpty else {
            throw DFTQualificationError.invalidEvidence("evidence identity and corpus revision are required")
        }
        guard evidence.processID == expectedProcessID else {
            throw DFTQualificationError.processMismatch(
                expected: expectedProcessID,
                actual: evidence.processID
            )
        }
        guard evidence.pdkDigest.caseInsensitiveCompare(expectedPDKDigest) == .orderedSame else {
            throw DFTQualificationError.pdkMismatch(
                expected: expectedPDKDigest,
                actual: evidence.pdkDigest
            )
        }
        guard isSHA256(evidence.pdkDigest), isSHA256(evidence.oracleEvidenceDigest) else {
            throw DFTQualificationError.invalidEvidence("PDK and oracle evidence digests must be SHA-256 values")
        }
        guard evidence.totalCaseCount > 0,
              evidence.passedCaseCount == evidence.totalCaseCount else {
            throw DFTQualificationError.invalidEvidence("all retained corpus cases must pass before promotion")
        }
        guard let approvedBy = evidence.approvedBy,
              !approvedBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DFTQualificationError.invalidEvidence("human or policy approver is required")
        }
        guard !evidence.artifacts.isEmpty else {
            throw DFTQualificationError.invalidEvidence(
                "at least one retained qualification artifact is required"
            )
        }
        for artifact in evidence.artifacts {
            guard isValidArtifact(artifact) else {
                throw DFTQualificationError.invalidEvidence(
                    "qualification artifacts require stable IDs, safe project-relative paths, SHA-256 digests and byte counts"
                )
            }
        }
        return DFTQualificationProvenance(
            status: .processQualified,
            corpusRevision: evidence.corpusRevision,
            oracleEvidence: evidence.oracleEvidenceDigest,
            processID: evidence.processID,
            pdkDigest: evidence.pdkDigest,
            notes: [
                "qualification gate accepted \(evidence.passedCaseCount) corpus case(s)",
                "oracle evidence digest was retained",
                "approval recorded by \(approvedBy)",
            ]
        )
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy { $0.isHexDigit }
    }

    private func isValidArtifact(_ artifact: XcircuiteFileReference) -> Bool {
        guard let artifactID = artifact.artifactID,
              !artifactID.isEmpty,
              !artifact.path.isEmpty,
              !artifact.path.hasPrefix("/"),
              !artifact.path.hasPrefix("~"),
              !artifact.path.contains("\\"),
              !artifact.path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !artifact.path.split(separator: "/", omittingEmptySubsequences: false)
                .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
              isSHA256(artifact.sha256 ?? ""),
              let byteCount = artifact.byteCount,
              byteCount >= 0 else {
            return false
        }
        guard artifactID.trimmingCharacters(in: .whitespacesAndNewlines) == artifactID else {
            return false
        }
        do {
            _ = try ArtifactID(rawValue: artifactID)
            return true
        } catch {
            return false
        }
    }
}
