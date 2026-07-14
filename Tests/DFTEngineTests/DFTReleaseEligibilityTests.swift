import DFTCore
import Foundation
import LogicIR
import PDKCore
import Testing
import TimingCore
import CircuiteFoundation

@Suite("DFT release eligibility")
struct DFTReleaseEligibilityTests {
    @Test("release gate accepts qualified DFT with complete downstream evidence and approval")
    func acceptsQualifiedCandidate() throws {
        let request = makeRequest()
        let digest = String(repeating: "a", count: 64)
        let artifacts = [
            artifact(id: "transformed-design", path: "dft/runs/release-run/transformed-design.json"),
            artifact(id: "design-diff", path: "dft/runs/release-run/design-diff.json")
        ]
        let payload = DFTPayload(
            transformedDesign: LogicDesignReference(
                artifact: artifacts[0].locator,
                topDesignName: "top",
                designDigest: digest
            ),
            faultCoverage: nil,
            designDiff: DFTDesignDiff(
                runID: request.runID,
                title: "Qualified scan insertion",
                actor: "dft",
                baseSnapshot: request.inputs[0],
                proposedSnapshot: artifacts[0],
                changes: []
            ),
            qualification: DFTQualificationProvenance(
                status: .processQualified,
                corpusRevision: "dft-corpus-r1",
                oracleEvidence: String(repeating: "b", count: 64),
                processID: request.pdk.processID,
                pdkDigest: request.pdk.digest
            )
        )
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            artifacts: artifacts,
            metadata: DFTExecutionMetadata(
                engineID: "dft.scan",
                implementationID: "qualified-scan",
                implementationVersion: "1",
                startedAt: Date(timeIntervalSince1970: 10),
                completedAt: Date(timeIntervalSince1970: 11)
            ),
            payload: payload
        )
        let downstream = DFTReleaseDownstreamEvidence.Domain.allCases.map { domain in
            DFTReleaseDownstreamEvidence(
                domain: domain,
                role: "\(domain.rawValue)-signoff",
                artifact: artifact(
                    id: "\(domain.rawValue)-report",
                    path: "signoff/\(domain.rawValue).json"
                )
            )
        }
        let approval = DFTReleaseReviewApproval(
            reviewerID: "human-reviewer",
            decision: .approved,
            reviewedAt: Date(timeIntervalSince1970: 12)
        )

        let eligibility = try DFTReleaseEligibilityGate().evaluate(
            request: request,
            result: result,
            downstreamEvidence: downstream,
            approval: approval
        )

        #expect(eligibility.status == DFTReleaseEligibilityStatus.eligible)
        #expect(eligibility.reviewResumeContract.decision == DFTReleaseReviewResumeContract.Decision.approved)
        #expect(Set(eligibility.downstreamDomains) == Set(DFTReleaseDownstreamEvidence.Domain.allCases))
    }

    @Test("release gate rejects qualified provenance bound to another PDK")
    func rejectsQualificationProvenanceForAnotherPDK() throws {
        let request = makeRequest()
        let transformed = artifact(id: "transformed-design", path: "dft/transformed.json")
        let payload = DFTPayload(
            transformedDesign: LogicDesignReference(
                artifact: transformed.locator,
                topDesignName: "top",
                designDigest: request.design.designDigest
            ),
            faultCoverage: nil,
            designDiff: DFTDesignDiff(
                runID: request.runID,
                title: "Qualified scan insertion",
                actor: "dft",
                baseSnapshot: request.inputs[0],
                proposedSnapshot: transformed,
                changes: []
            ),
            qualification: DFTQualificationProvenance(
                status: .processQualified,
                corpusRevision: "dft-corpus-r1",
                oracleEvidence: String(repeating: "b", count: 64),
                processID: request.pdk.processID,
                pdkDigest: String(repeating: "f", count: 64)
            )
        )
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            artifacts: [transformed, artifact(id: "design-diff", path: "dft/diff.json")],
            metadata: DFTExecutionMetadata(
                engineID: "dft.scan",
                implementationID: "qualified-scan",
                implementationVersion: "1",
                startedAt: Date(timeIntervalSince1970: 10),
                completedAt: Date(timeIntervalSince1970: 11)
            ),
            payload: payload
        )

        do {
            _ = try DFTReleaseEligibilityGate().evaluate(
                request: request,
                result: result,
                downstreamEvidence: [],
                approval: nil
            )
            Issue.record("DFT release must reject qualification provenance for another PDK")
        } catch let error as DFTReleaseEligibilityError {
            #expect(error == .qualificationProvenanceInvalid(
                "process ID, PDK digest and SHA-256 oracle evidence must match the request"
            ))
        }
    }

    @Test("release gate blocks smoke-qualified candidate before downstream signoff")
    func blocksSmokeQualification() throws {
        let request = makeRequest()
        let result = DFTResult(
            schemaVersion: DFTRequest.currentSchemaVersion,
            runID: request.runID,
            status: .completed,
            artifacts: [artifact(id: "transformed-design", path: "dft/transformed.json")],
            metadata: DFTExecutionMetadata(
                engineID: "dft.scan",
                implementationID: "native",
                implementationVersion: "1",
                startedAt: Date(timeIntervalSince1970: 10),
                completedAt: Date(timeIntervalSince1970: 11)
            ),
            payload: DFTPayload(
                transformedDesign: LogicDesignReference(
                    artifact: artifact(id: "transformed-design", path: "dft/transformed.json").locator,
                    topDesignName: "top",
                    designDigest: String(repeating: "a", count: 64)
                ),
                faultCoverage: nil,
                designDiff: DFTDesignDiff(
                    runID: request.runID,
                    title: "Smoke scan insertion",
                    actor: "dft",
                    baseSnapshot: request.inputs[0],
                    proposedSnapshot: artifact(id: "transformed-design", path: "dft/transformed.json"),
                    changes: []
                ),
                qualification: DFTQualificationProvenance(status: .smokeChecked)
            )
        )

        do {
            _ = try DFTReleaseEligibilityGate().evaluate(
                request: request,
                result: result,
                downstreamEvidence: [],
                approval: nil
            )
            Issue.record("Smoke-qualified DFT must not be release eligible")
        } catch let error as DFTReleaseEligibilityError {
            #expect(error == .qualificationInsufficient(.smokeChecked))
        }
    }

    private func makeRequest() -> DFTRequest {
        let designArtifact = artifact(id: "design", path: "design.json")
        return DFTRequest(
            runID: "release-run",
            inputs: [designArtifact],
            design: LogicDesignReference(
                artifact: designArtifact.locator,
                topDesignName: "top",
                designDigest: String(repeating: "c", count: 64)
            ),
            constraints: DFTConstraintReference(
                artifact: artifact(id: "constraints", path: "test.sdc"),
                modeIDs: ["test"]
            ),
            pdk: PDKReference(
                manifest: artifact(id: "pdk", path: "pdk.json"),
                processID: "fixture-process",
                version: "1",
                digest: String(repeating: "d", count: 64)
            ),
            operation: .scanInsertion
        )
    }

    private func artifact(id: String, path: String) -> ArtifactReference {
        testArtifact(
            artifactID: id,
            path: path,
            kind: .report,
            format: .json,
            sha256: String(repeating: "e", count: 64),
            byteCount: 1,
            role: .output
        )
    }
}

private extension DFTReleaseDownstreamEvidence.Domain {
    static var allCases: [Self] {
        [.equivalence, .drc, .lvs, .pex]
    }
}
