import DFTCore
import Foundation
import LogicIR
import Testing
import CircuiteFoundation

@Suite("DFT oracle correlation")
struct DFTOracleCorrelationTests {
    @Test("correlates retained oracle expectations into raw observations")
    func correlatesRetainedOracle() async throws {
        let requestDigest = String(repeating: "d", count: 64)
        let pdkDigest = String(repeating: "c", count: 64)
        let faultUniverseDigest = String(repeating: "f", count: 64)
        let result = try makeResult(faultUniverseDigest: faultUniverseDigest)
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

        #expect(correlation.processID == corpus.processID)
        #expect(correlation.pdkDigest == corpus.pdkDigest)
    }

    @Test("mismatched oracle outcome remains a raw mismatch")
    func mismatchedOracleRemainsMismatched() async throws {
        let requestDigest = String(repeating: "d", count: 64)
        let pdkDigest = String(repeating: "c", count: 64)
        let corpus = makeCorpus(
            requestDigest: requestDigest,
            pdkDigest: pdkDigest,
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let mismatchedResult = try makeResult(
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

    @Test("duplicate native observations are rejected")
    func duplicateObservationsAreRejected() async throws {
        let digest = String(repeating: "d", count: 64)
        let corpus = makeCorpus(
            requestDigest: digest,
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let observation = DFTOracleCaseObservation(
            caseID: "case-1",
            operation: .atpg,
            requestDigest: digest,
            result: try makeResult(faultUniverseDigest: String(repeating: "f", count: 64))
        )

        await #expect(throws: DFTOracleCorrelationError.duplicateObservation("case-1")) {
            try await DFTOracleCorrelationEngine().correlate(
                corpus: corpus,
                observations: [observation, observation]
            )
        }
    }

    @Test("observations outside the retained corpus are rejected")
    func unknownObservationIsRejected() async throws {
        let corpus = makeCorpus(
            requestDigest: String(repeating: "d", count: 64),
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let observation = DFTOracleCaseObservation(
            caseID: "unknown-case",
            operation: .atpg,
            requestDigest: String(repeating: "d", count: 64),
            result: try makeResult(faultUniverseDigest: String(repeating: "f", count: 64))
        )

        await #expect(throws: DFTOracleCorrelationError.unknownObservation("unknown-case")) {
            try await DFTOracleCorrelationEngine().correlate(corpus: corpus, observations: [observation])
        }
    }

    @Test("a corpus requires a canonical PDK digest")
    func invalidPDKDigestIsRejected() async throws {
        let corpus = makeCorpus(
            requestDigest: String(repeating: "d", count: 64),
            pdkDigest: "not-a-digest",
            faultUniverseDigest: String(repeating: "f", count: 64)
        )

        await #expect(throws: DFTOracleCorrelationError.self) {
            try await DFTOracleCorrelationEngine().correlate(corpus: corpus, observations: [])
        }
    }

    @Test("corpus case identities must be unique")
    func duplicateCorpusCaseIsRejected() async throws {
        let base = makeCorpus(
            requestDigest: String(repeating: "d", count: 64),
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let corpus = DFTOracleCorpus(
            corpusID: base.corpusID,
            revision: base.revision,
            processID: base.processID,
            pdkDigest: base.pdkDigest,
            cases: [base.cases[0], base.cases[0]]
        )

        await #expect(throws: DFTOracleCorrelationError.self) {
            try await DFTOracleCorrelationEngine().correlate(corpus: corpus, observations: [])
        }
    }

    @Test("request binding mismatches remain explicit raw evidence")
    func requestDigestMismatchIsReported() async throws {
        let corpus = makeCorpus(
            requestDigest: String(repeating: "d", count: 64),
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: String(repeating: "f", count: 64)
        )
        let observation = DFTOracleCaseObservation(
            caseID: "case-1",
            operation: .atpg,
            requestDigest: String(repeating: "a", count: 64),
            result: try makeResult(faultUniverseDigest: String(repeating: "f", count: 64))
        )

        let correlation = try await DFTOracleCorrelationEngine().correlate(
            corpus: corpus,
            observations: [observation]
        )

        #expect(correlation.status == .mismatched)
        #expect(correlation.diagnostics.contains { $0.contains("request digest") })
    }

    @Test("correlation evidence digest is deterministic")
    func correlationDigestIsDeterministic() async throws {
        let digest = String(repeating: "d", count: 64)
        let faultDigest = String(repeating: "f", count: 64)
        let corpus = makeCorpus(
            requestDigest: digest,
            pdkDigest: String(repeating: "c", count: 64),
            faultUniverseDigest: faultDigest
        )
        let observation = DFTOracleCaseObservation(
            caseID: "case-1",
            operation: .atpg,
            requestDigest: digest,
            result: try makeResult(faultUniverseDigest: faultDigest)
        )
        let engine = DFTOracleCorrelationEngine()

        let first = try await engine.correlate(corpus: corpus, observations: [observation])
        let second = try await engine.correlate(corpus: corpus, observations: [observation])

        #expect(first.corpusDigest == second.corpusDigest)
        #expect(first.oracleEvidenceDigest == second.oracleEvidenceDigest)
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
                oracleArtifact: testArtifact(
                    artifactID: "oracle-case-1",
                    path: "evidence/oracle-case-1.json",
                    kind: .report,
                    format: .json,
                    sha256: String(repeating: "e", count: 64),
                    byteCount: 128,
                    role: .output
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
        let oracleArtifact = testArtifact(
            artifactID: "oracle-case-1",
            path: "evidence/oracle-case-1.json",
            kind: .report,
            format: .json,
            sha256: try SHA256ContentDigester().digest(data: oracleData, using: .sha256).hexadecimalValue,
            byteCount: Int64(oracleData.count),
            role: .output
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
    ) throws -> DFTResult {
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
            evidenceProvenance: DFTEvidenceProvenance(status: .smokeObserved),
            outcomes: [DFTFaultOutcome(
                faultID: faultID,
                status: .detected,
                patternID: "pattern-1",
                reason: "fixture"
            )]
        )
        return DFTResult(
            schemaVersion: 1,
            runID: "native-run",
            status: .completed,
            provenance: try DFTExecutionSupport.provenance(
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
                evidenceProvenance: DFTEvidenceProvenance(status: .smokeObserved)
            )
        )
    }
}
