import Foundation
import CircuiteFoundation

public struct DFTReleaseEligibilityGate: Sendable {
    public init() {}

    public func evaluate(
        request: DFTRequest,
        result: DFTResult,
        downstreamEvidence: [DFTReleaseDownstreamEvidence],
        approval: DFTReleaseReviewApproval? = nil,
        sourceStageID: String = "dft",
        resumeStageID: String = "dft.review-resume"
    ) throws -> DFTReleaseEligibility {
        guard result.runID == request.runID else {
            throw DFTReleaseEligibilityError.runIDMismatch(
                expected: request.runID,
                actual: result.runID
            )
        }
        guard result.schemaVersion == DFTRequest.currentSchemaVersion else {
            throw DFTReleaseEligibilityError.invalidExecutionMetadata(
                "result schema version \(result.schemaVersion) is unsupported"
            )
        }
        guard result.status == .completed else {
            throw DFTReleaseEligibilityError.executionNotCompleted(result.status.rawValue)
        }
        guard !result.metadata.engineID.isEmpty,
              !result.metadata.implementationID.isEmpty,
              result.metadata.completedAt >= result.metadata.startedAt else {
            throw DFTReleaseEligibilityError.invalidExecutionMetadata(
                "engine and implementation IDs are required and completedAt must not precede startedAt"
            )
        }

        let artifactIDs = try validatedArtifactIDs(result.artifacts)
        switch request.operation {
        case .scanInsertion, .bist:
            guard let transformedDesign = result.payload.transformedDesign else {
                throw DFTReleaseEligibilityError.transformedDesignMissing
            }
            guard let designDiff = result.payload.designDiff else {
                throw DFTReleaseEligibilityError.designDiffMissing
            }
            guard designDiff.runID == request.runID else {
                throw DFTReleaseEligibilityError.designDiffInvalid(
                    "design diff run ID (designDiff.runID) does not match request run ID (request.runID)"
                )
            }
            guard designDiff.baseSnapshot?.locator == request.design.artifact else {
                throw DFTReleaseEligibilityError.designDiffInvalid(
                    "design diff base snapshot does not match the requested source design artifact"
                )
            }
            guard designDiff.proposedSnapshot?.locator == transformedDesign.artifact else {
                throw DFTReleaseEligibilityError.designDiffInvalid(
                    "design diff proposed snapshot does not match the transformed design artifact"
                )
            }
        case .atpg:
            try validateCoverage(result.payload)
        case nil:
            throw DFTReleaseEligibilityError.invalidReviewContract(
                "release evaluation requires an explicit DFT operation"
            )
        }

        guard result.payload.qualification.status == .processQualified else {
            throw DFTReleaseEligibilityError.qualificationInsufficient(
                result.payload.qualification.status
            )
        }
        guard result.payload.qualification.processID == request.pdk.processID,
              let corpusRevision = result.payload.qualification.corpusRevision,
              !corpusRevision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              result.payload.qualification.pdkDigest?.caseInsensitiveCompare(request.pdk.digest) == .orderedSame,
              let oracleEvidence = result.payload.qualification.oracleEvidence,
              isSHA256(oracleEvidence) else {
            throw DFTReleaseEligibilityError.qualificationProvenanceInvalid(
                "process ID, PDK digest and SHA-256 oracle evidence must match the request"
            )
        }
        let domains = try validatedDownstreamEvidence(downstreamEvidence)
        guard domains.contains(.equivalence) else {
            throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                "equivalence evidence is required"
            )
        }
        guard domains.contains(.drc) else {
            throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                "DRC evidence is required"
            )
        }
        guard domains.contains(.lvs) else {
            throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                "LVS evidence is required"
            )
        }
        guard domains.contains(.pex) else {
            throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                "PEX evidence is required"
            )
        }
        guard let approval else {
            throw DFTReleaseEligibilityError.approvalRequired
        }
        guard approval.decision == .approved else {
            throw DFTReleaseEligibilityError.approvalRejected
        }
        guard !approval.reviewerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DFTReleaseEligibilityError.invalidReviewContract(
                "approved review must identify a reviewer"
            )
        }

        let contract = DFTReleaseReviewResumeContract(
            runID: request.runID,
            sourceStageID: sourceStageID,
            resumeStageID: resumeStageID,
            designDigest: request.design.designDigest,
            candidateArtifactIDs: artifactIDs,
            decision: .approved
        )
        return DFTReleaseEligibility(
            runID: request.runID,
            status: .eligible,
            requiredArtifactIDs: artifactIDs,
            downstreamDomains: domains,
            reviewApproval: approval,
            reviewResumeContract: contract
        )
    }

    private func validatedArtifactIDs(
        _ artifacts: [DFTArtifactReference]
    ) throws -> [String] {
        guard !artifacts.isEmpty else {
            throw DFTReleaseEligibilityError.invalidArtifactReference(
                "at least one DFT artifact is required"
            )
        }
        var artifactIDs = Set<String>()
        for artifact in artifacts {
            guard let artifactID = artifact.artifactID,
                  isValidArtifactID(artifactID),
                  artifactIDs.insert(artifactID).inserted else {
                throw DFTReleaseEligibilityError.invalidArtifactReference(
                    "artifact IDs must be present and unique"
                )
            }
            guard isSafeArtifactPath(artifact.path) else {
                throw DFTReleaseEligibilityError.invalidArtifactReference(
                    "artifact paths must be project-relative"
                )
            }
            guard let digest = artifact.sha256,
                  digest.count == 64,
                  digest.allSatisfy(\.isHexDigit),
                  artifact.byteCount >= 0 else {
                throw DFTReleaseEligibilityError.invalidArtifactReference(
                    "artifact \(artifactID) requires SHA-256 and non-negative byte count"
                )
            }
        }
        return artifactIDs.sorted()
    }

    private func validateCoverage(_ payload: DFTPayload) throws {
        guard let evidence = payload.coverageEvidence else {
            throw DFTReleaseEligibilityError.coverageEvidenceMissing
        }
        let activeFaultCount = evidence.declaredFaultCount - evidence.excludedFaultCount
        let detectedCount = evidence.outcomes.filter { $0.status == .detected }.count
        let untestableCount = evidence.outcomes.filter { $0.status == .untestable }.count
        let abortedCount = evidence.outcomes.filter { $0.status == .aborted }.count
        let outcomeIDs = evidence.outcomes.map(\.faultID)
        guard let coverage = evidence.coverage,
              coverage == 1.0,
              evidence.declaredFaultCount > 0,
              evidence.excludedFaultCount >= 0,
              evidence.excludedFaultCount <= evidence.declaredFaultCount,
              activeFaultCount == evidence.outcomes.count,
              Set(outcomeIDs).count == outcomeIDs.count,
              evidence.detectedFaultCount == detectedCount,
              evidence.untestableFaultCount == untestableCount,
              evidence.abortedFaultCount == abortedCount,
              detectedCount == activeFaultCount,
              untestableCount == 0,
              abortedCount == 0 else {
            throw DFTReleaseEligibilityError.coverageIncomplete(
                "all declared active faults must be detected without untestable or aborted outcomes"
            )
        }
        guard evidence.outcomes.allSatisfy({ $0.status == .detected }) else {
            throw DFTReleaseEligibilityError.coverageIncomplete(
                "every retained fault outcome must be detected"
            )
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private func isValidArtifactID(_ value: String) -> Bool {
        do {
            _ = try ArtifactID(rawValue: value)
            return true
        } catch {
            return false
        }
    }

    private func isSafeArtifactPath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        return !path.split(separator: "/", omittingEmptySubsequences: false)
            .contains(where: { $0.isEmpty || $0 == "." || $0 == ".." })
    }

    private func validatedDownstreamEvidence(
        _ evidence: [DFTReleaseDownstreamEvidence]
    ) throws -> [DFTReleaseDownstreamEvidence.Domain] {
        guard !evidence.isEmpty else {
            throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                "no downstream evidence was supplied"
            )
        }
        var seen = Set<DFTReleaseDownstreamEvidence.Domain>()
        for item in evidence {
            guard !item.role.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                    "downstream evidence roles must be non-empty"
                )
            }
            _ = try validatedArtifactIDs([item.artifact])
            guard seen.insert(item.domain).inserted else {
                throw DFTReleaseEligibilityError.downstreamEvidenceMissing(
                    "downstream domains must be unique"
                )
            }
        }
        return seen.sorted { $0.rawValue < $1.rawValue }
    }
}
