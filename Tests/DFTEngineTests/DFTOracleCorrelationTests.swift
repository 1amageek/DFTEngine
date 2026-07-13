import DFTCore
import Foundation
import LogicIR
import Testing
import XcircuitePackage

@Suite("DFT oracle correlation")
struct DFTOracleCorrelationTests {
    @Test("correlates retained oracle expectations and creates qualification evidence")
    func correlatesRetainedOracle() async throws {
        let requestDigest = String(repeating: "d", count: 64)
        let pdkDigest = String(repeating: "c", count: 64)
        let faultUniverseDigest = String(repeating: "f", count: 64)
        let result = makeResult(faultUniverseDigest: faultUniverseDigest)
        let (corpus, oracleData) = try makeVerifiedCorpus(
            requestDigest: requestDigest,
            pdkDigest: pdkDigest,
            faultUniverseDigest: faultUniverseDigest
        )
        let observation = DFTOracleCaseObservation(
            caseID: "case-1",
            operation: .atpg,
            requestDigest: requestDigest,
            result: result
        )

        let loader = InMemoryDFTOracleArtifactLoader(
            artifacts: [corpus.cases[0].oracleArtifact.path: oracleData]
        )
        let correlation = try await DFTOracleCorrelationEngine(artifactLoader: loader).correlate(
            corpus: corpus,
            observations: [observation]
        )
        #expect(correlation.status == .correlated)
        #expect(correlation.passedCaseCount == 1)
        #expect(correlation.oracleEvidenceDigest.count == 64)

        let evidence = try correlation.makeQualificationEvidence(
            evidenceID: "qualification-1",
            engineID: "dft.atpg",
            implementationID: "native-deterministic-atpg",
            approvedBy: "reviewer",
            artifacts: [corpus.cases[0].oracleArtifact]
        )
        let provenance = try DFTQualificationGate().evaluate(
            evidence,
            expectedProcessID: corpus.processID,
            expectedPDKDigest: corpus.pdkDigest
        )
        #expect(provenance.status == .processQualified)
        #expect(provenance.oracleEvidence == correlation.oracleEvidenceDigest)
    }

    @Test("mismatched oracle outcome cannot be promoted")
    func mismatchedOracleCannotBePromoted() async throws {
        let requestDigest = String(repeating: "d", count: 64)
        let pdkDigest = String(repeating: "c", count: 64)
        let corpus = makeCorpus(
            requestDigest: requestDigest,
            pdkDigest: pdkDigest,
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let mismatchedResult = makeResult(
            faultUniverseDigest: String(repeating: "f", count: 64),
            faultID: "different-fault"
        )
        let observation = DFTOracleCaseObservation(
            caseID: "case-1",
            operation: .atpg,
            requestDigest: requestDigest,
            result: mismatchedResult
        )

        let correlation = try await DFTOracleCorrelationEngine().correlate(
            corpus: corpus,
            observations: [observation]
        )
        #expect(correlation.status == .mismatched)
        #expect(correlation.passedCaseCount == 0)
        #expect(correlation.diagnostics.contains { $0.contains("detected fault IDs") })

        var didThrow = false
        do {
            _ = try correlation.makeQualificationEvidence(
                evidenceID: "qualification-mismatch",
                engineID: "dft.atpg",
                implementationID: "native-deterministic-atpg",
                approvedBy: "reviewer"
            )
        } catch {
            didThrow = true
        }
        #expect(didThrow)
    }

    @Test("missing oracle observation remains incomplete")
    func missingObservationRemainsIncomplete() async throws {
        let corpus = makeCorpus(
            requestDigest: String(repeating: "d", count: 64),
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let correlation = try await DFTOracleCorrelationEngine().correlate(
            corpus: corpus,
            observations: []
        )
        #expect(correlation.status == .incomplete)
        #expect(correlation.passedCaseCount == 0)
        #expect(correlation.diagnostics.contains { $0.contains("native observation is missing") })
    }

    private func makeCorpus(
        requestDigest: String,
        pdkDigest: String,
        faultUniverseDigest: String
    ) -> DFTOracleCorpus {
        DFTOracleCorpus(
            corpusID: "fixture-oracle",
            revision: "oracle-r1",
            processID: "fixture-process",
            pdkDigest: pdkDigest,
            cases: [DFTOracleCorpusCase(
                caseID: "case-1",
                operation: .atpg,
                requestDigest: requestDigest,
                expectation: DFTOracleCaseExpectation(
                    expectedStatus: .completed,
                    expectedFaultUniverseDigest: faultUniverseDigest,
                    expectedDetectedFaultIDs: ["fault-1"],
                    expectedCoverage: 1.0
                ),
                oracleArtifact: XcircuiteFileReference(
                    artifactID: "oracle-case-1",
                    path: "qualification/oracle-case-1.json",
                    kind: .report,
                    format: .json,
                    sha256: String(repeating: "e", count: 64),
                    byteCount: 128
                )
            )]
        )
    }

    private func makeVerifiedCorpus(
        requestDigest: String,
        pdkDigest: String,
        faultUniverseDigest: String
    ) throws -> (DFTOracleCorpus, Data) {
        let expectation = DFTOracleCaseExpectation(
            expectedStatus: .completed,
            expectedFaultUniverseDigest: faultUniverseDigest,
            expectedDetectedFaultIDs: ["fault-1"],
            expectedCoverage: 1.0
        )
        let oracleData = try DFTArtifactJSONEncoder().encode(expectation)
        let oracleArtifact = XcircuiteFileReference(
            artifactID: "oracle-case-1",
            path: "qualification/oracle-case-1.json",
            kind: .report,
            format: .json,
            sha256: XcircuiteHasher().sha256(data: oracleData),
            byteCount: Int64(oracleData.count)
        )
        let corpus = DFTOracleCorpus(
            corpusID: "fixture-oracle",
            revision: "oracle-r1",
            processID: "fixture-process",
            pdkDigest: pdkDigest,
            cases: [DFTOracleCorpusCase(
                caseID: "case-1",
                operation: .atpg,
                requestDigest: requestDigest,
                expectation: expectation,
                oracleArtifact: oracleArtifact
            )]
        )
        return (corpus, oracleData)
    }

    private func makeResult(
        faultUniverseDigest: String,
        faultID: String = "fault-1"
    ) -> XcircuiteEngineResultEnvelope<DFTPayload> {
        let coverage = DFTCoverageEvidence(
            faultUniverseName: "fixture-faults",
            faultUniverseRevision: "r1",
            faultUniverseDigest: faultUniverseDigest,
            declaredFaultCount: 1,
            excludedFaultCount: 0,
            detectedFaultCount: 1,
            untestableFaultCount: 0,
            abortedFaultCount: 0,
            coverage: 1.0,
            assumptions: ["fixture oracle"],
            qualification: DFTQualificationProvenance(status: .smokeChecked),
            outcomes: [DFTFaultOutcome(
                faultID: faultID,
                status: .detected,
                patternID: "pattern-1",
                reason: "fixture"
            )]
        )
        return XcircuiteEngineResultEnvelope(
            schemaVersion: 1,
            runID: "native-run",
            status: .completed,
            metadata: XcircuiteEngineExecutionMetadata(
                engineID: "dft.atpg",
                implementationID: "native-deterministic-atpg",
                implementationVersion: "1",
                startedAt: Date(timeIntervalSince1970: 0),
                completedAt: Date(timeIntervalSince1970: 1),
                seed: 1
            ),
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: 1.0,
                coverageEvidence: coverage,
                qualification: DFTQualificationProvenance(status: .smokeChecked)
            )
        )
    }
}
