import Testing
import CircuiteFoundation
@testable import DFTCore
@testable import ScanInsertion
@testable import ATPGEngine
@testable import BISTEngine
@testable import DFTEngine

@Suite("DFTEngine contract")
struct ContractTests {
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(DFTEngineAPI.contractVersion == 1)
    }

    @Test("qualification gate promotes only complete approved evidence")
    func qualificationGate() throws {
        let digest = String(repeating: "a", count: 64)
        let evidence = DFTQualificationEvidence(
            evidenceID: "qualification-1",
            engineID: "dft.atpg",
            implementationID: "native-deterministic-atpg",
            processID: "fixture-process",
            pdkDigest: digest,
            corpusRevision: "corpus-1",
            totalCaseCount: 4,
            passedCaseCount: 4,
            oracleEvidenceDigest: String(repeating: "b", count: 64),
            approvedBy: "reviewer",
            artifacts: [qualificationArtifact()]
        )

        let provenance = try DFTQualificationGate().evaluate(
            evidence,
            expectedProcessID: "fixture-process",
            expectedPDKDigest: digest
        )

        #expect(provenance.status == .processQualified)
        #expect(provenance.processID == "fixture-process")
    }

    @Test("qualification gate blocks evidence without retained artifacts")
    func qualificationGateBlocksMissingArtifacts() throws {
        let digest = String(repeating: "a", count: 64)
        let evidence = DFTQualificationEvidence(
            evidenceID: "qualification-without-artifact",
            engineID: "dft.atpg",
            implementationID: "native-deterministic-atpg",
            processID: "fixture-process",
            pdkDigest: digest,
            corpusRevision: "corpus-1",
            totalCaseCount: 1,
            passedCaseCount: 1,
            oracleEvidenceDigest: String(repeating: "b", count: 64),
            approvedBy: "reviewer"
        )

        var didThrow = false
        do {
            _ = try DFTQualificationGate().evaluate(
                evidence,
                expectedProcessID: "fixture-process",
                expectedPDKDigest: digest
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("qualification gate blocks incomplete corpus evidence")
    func qualificationGateBlocksIncompleteEvidence() throws {
        let evidence = DFTQualificationEvidence(
            evidenceID: "qualification-incomplete",
            engineID: "dft.atpg",
            implementationID: "native-deterministic-atpg",
            processID: "fixture-process",
            pdkDigest: String(repeating: "a", count: 64),
            corpusRevision: "corpus-1",
            totalCaseCount: 4,
            passedCaseCount: 3,
            oracleEvidenceDigest: String(repeating: "b", count: 64)
        )
        var didThrow = false
        do {
            _ = try DFTQualificationGate().evaluate(
                evidence,
                expectedProcessID: "fixture-process",
                expectedPDKDigest: evidence.pdkDigest
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    private func qualificationArtifact() -> ArtifactReference {
        testArtifact(
            artifactID: "qualification-corpus",
            path: "qualification/corpus.json",
            kind: .report,
            format: .json,
            sha256: String(repeating: "c", count: 64),
            byteCount: 1,
            role: .output
        )
    }
}
