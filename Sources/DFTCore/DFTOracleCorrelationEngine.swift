import Foundation
import XcircuitePackage

public struct DFTOracleCorrelationEngine: DFTOracleCorrelating {
    public let artifactLoader: (any DFTOracleArtifactLoading)?

    public init(artifactLoader: (any DFTOracleArtifactLoading)? = nil) {
        self.artifactLoader = artifactLoader
    }

    public func correlate(
        corpus: DFTOracleCorpus,
        observations: [DFTOracleCaseObservation]
    ) async throws -> DFTOracleCorrelationResult {
        try validate(corpus: corpus)
        try await validateOracleArtifacts(corpus)
        var observationsByID: [String: DFTOracleCaseObservation] = [:]
        for observation in observations {
            guard observationsByID[observation.caseID] == nil else {
                throw DFTOracleCorrelationError.duplicateObservation(observation.caseID)
            }
            guard corpus.cases.contains(where: { $0.caseID == observation.caseID }) else {
                throw DFTOracleCorrelationError.unknownObservation(observation.caseID)
            }
            guard !observation.caseID.isEmpty,
                  !observation.requestDigest.isEmpty,
                  !observation.result.runID.isEmpty else {
                throw DFTOracleCorrelationError.invalidObservation(
                    "case ID, request digest and result run ID are required"
                )
            }
            observationsByID[observation.caseID] = observation
        }

        let corpusDigest = try DFTDeterministicHasher().digest(corpus)
        let correlations = try corpus.cases.map { corpusCase in
            guard let observation = observationsByID[corpusCase.caseID] else {
                return DFTOracleCaseCorrelation(
                    caseID: corpusCase.caseID,
                    status: .missingObservation,
                    mismatches: ["native observation is missing"]
                )
            }
            return try compare(corpusCase: corpusCase, observation: observation)
        }
        let passedCaseCount = correlations.filter { $0.status == .matched }.count
        let status: DFTOracleCorrelationStatus
        if correlations.contains(where: { $0.status == .missingObservation }) {
            status = .incomplete
        } else if passedCaseCount == corpus.cases.count {
            status = .correlated
        } else {
            status = .mismatched
        }
        let diagnostics = correlations
            .filter { $0.status != .matched }
            .flatMap { correlation in
                correlation.mismatches.map { correlation.caseID + ": " + $0 }
            }
        let evidenceMaterial = corpusDigest + "|" + correlations.map { correlation in
            let mismatches = correlation.mismatches.joined(separator: ",")
            return correlation.caseID + ":" + correlation.status.rawValue + ":" + (correlation.nativeResultDigest ?? "") + ":" + mismatches
        }.joined(separator: "|")

        return DFTOracleCorrelationResult(
            corpusID: corpus.corpusID,
            corpusRevision: corpus.revision,
            processID: corpus.processID,
            pdkDigest: corpus.pdkDigest,
            corpusDigest: corpusDigest,
            oracleEvidenceDigest: XcircuiteHasher().sha256(data: Data(evidenceMaterial.utf8)),
            status: status,
            totalCaseCount: corpus.cases.count,
            passedCaseCount: passedCaseCount,
            cases: correlations,
            diagnostics: diagnostics
        )
    }

    private func validate(corpus: DFTOracleCorpus) throws {
        guard corpus.schemaVersion == DFTOracleCorpus.currentSchemaVersion else {
            throw DFTOracleCorrelationError.invalidCorpus("unsupported schema version " + String(corpus.schemaVersion))
        }
        guard !corpus.corpusID.isEmpty,
              !corpus.revision.isEmpty,
              !corpus.processID.isEmpty,
              !corpus.cases.isEmpty else {
            throw DFTOracleCorrelationError.invalidCorpus(
                "corpus ID, revision, process ID and at least one case are required"
            )
        }
        guard isSHA256(corpus.pdkDigest) else {
            throw DFTOracleCorrelationError.invalidCorpus("PDK digest must be a SHA-256 value")
        }
        var caseIDs = Set<String>()
        for corpusCase in corpus.cases {
            guard !corpusCase.caseID.isEmpty,
                  caseIDs.insert(corpusCase.caseID).inserted else {
                throw DFTOracleCorrelationError.invalidCorpus("case IDs must be non-empty and unique")
            }
            guard isSHA256(corpusCase.requestDigest) else {
                throw DFTOracleCorrelationError.invalidCorpus(
                    "case " + corpusCase.caseID + " request digest must be a SHA-256 value"
                )
            }
            try validate(artifact: corpusCase.oracleArtifact, caseID: corpusCase.caseID)
            if let coverage = corpusCase.expectation.expectedCoverage,
               !coverage.isFinite || coverage < 0 || coverage > 1 {
                throw DFTOracleCorrelationError.invalidCorpus(
                    "case " + corpusCase.caseID + " coverage must be within [0, 1]"
                )
            }
        }
    }

    private func validate(artifact: XcircuiteFileReference, caseID: String) throws {
        guard artifact.artifactID?.isEmpty == false,
              !artifact.path.isEmpty,
              !artifact.path.hasPrefix("/"),
              !artifact.path.split(separator: "/").contains(".."),
              artifact.sha256.map(isSHA256) == true,
              artifact.byteCount.map({ $0 >= 0 }) == true else {
            throw DFTOracleCorrelationError.invalidCorpus(
                "oracle artifact for case " + caseID + " must be project-relative and integrity-addressed"
            )
        }
    }

    private func validateOracleArtifacts(_ corpus: DFTOracleCorpus) async throws {
        guard let artifactLoader else { return }
        let decoder = JSONDecoder()
        for corpusCase in corpus.cases {
            let data = try await artifactLoader.load(corpusCase.oracleArtifact)
            let artifactExpectation: DFTOracleCaseExpectation
            do {
                artifactExpectation = try decoder.decode(DFTOracleCaseExpectation.self, from: data)
            } catch {
                throw DFTOracleCorrelationError.invalidCorpus(
                    "oracle artifact for case " + corpusCase.caseID + " is not a normalized expectation JSON: " + error.localizedDescription
                )
            }
            guard artifactExpectation == corpusCase.expectation else {
                throw DFTOracleCorrelationError.invalidCorpus(
                    "oracle artifact expectation does not match corpus declaration for case " + corpusCase.caseID
                )
            }
        }
    }

    private func compare(
        corpusCase: DFTOracleCorpusCase,
        observation: DFTOracleCaseObservation
    ) throws -> DFTOracleCaseCorrelation {
        let hasher = DFTDeterministicHasher()
        let nativeResultDigest = try hasher.digest(observation.result)
        let expectation = corpusCase.expectation
        var mismatches: [String] = []
        if observation.operation != corpusCase.operation {
            mismatches.append("operation expected " + corpusCase.operation.rawValue + ", got " + observation.operation.rawValue)
        }
        if observation.requestDigest != corpusCase.requestDigest {
            mismatches.append("request digest does not match the retained corpus case")
        }
        if observation.result.status != expectation.expectedStatus {
            mismatches.append("execution status expected " + expectation.expectedStatus.rawValue + ", got " + observation.result.status.rawValue)
        }
        if let expected = expectation.expectedTransformedDesignDigest,
           observation.result.payload.transformedDesign?.designDigest != expected {
            mismatches.append("transformed design digest does not match the oracle")
        }
        if let expected = expectation.expectedFaultUniverseDigest,
           observation.result.payload.coverageEvidence?.faultUniverseDigest != expected {
            mismatches.append("fault universe digest does not match the oracle")
        }
        if let coverageEvidence = observation.result.payload.coverageEvidence {
            compareIDs(
                outcomeIDs(coverageEvidence, status: .detected),
                expectation.expectedDetectedFaultIDs,
                label: "detected fault IDs",
                mismatches: &mismatches
            )
            compareIDs(
                outcomeIDs(coverageEvidence, status: .untestable),
                expectation.expectedUntestableFaultIDs,
                label: "untestable fault IDs",
                mismatches: &mismatches
            )
            compareIDs(
                outcomeIDs(coverageEvidence, status: .aborted),
                expectation.expectedAbortedFaultIDs,
                label: "aborted fault IDs",
                mismatches: &mismatches
            )
            if let expected = expectation.expectedCoverage,
               coverageEvidence.coverage != expected {
                let actual = coverageEvidence.coverage.map { String($0) } ?? "nil"
                mismatches.append("coverage expected " + String(expected) + ", got " + actual)
            }
        } else if expectation.expectedFaultUniverseDigest != nil
                    || !expectation.expectedDetectedFaultIDs.isEmpty
                    || !expectation.expectedUntestableFaultIDs.isEmpty
                    || !expectation.expectedAbortedFaultIDs.isEmpty
                    || expectation.expectedCoverage != nil {
            mismatches.append("coverage evidence is missing")
        }
        if let expected = expectation.expectedPatternDigest {
            if let patterns = observation.result.payload.patterns {
                let actual = try hasher.digest(patterns)
                if actual != expected {
                    mismatches.append("pattern digest does not match the oracle")
                }
            } else {
                mismatches.append("pattern set is missing")
            }
        }
        if let expected = expectation.expectedBISTStructureDigest {
            if let bistStructure = observation.result.payload.bistStructure {
                let actual = try hasher.digest(bistStructure)
                if actual != expected {
                    mismatches.append("BIST structure digest does not match the oracle")
                }
            } else {
                mismatches.append("BIST structure is missing")
            }
        }
        return DFTOracleCaseCorrelation(
            caseID: corpusCase.caseID,
            status: mismatches.isEmpty ? .matched : .mismatched,
            nativeResultDigest: nativeResultDigest,
            mismatches: mismatches
        )
    }

    private func outcomeIDs(
        _ evidence: DFTCoverageEvidence,
        status: DFTFaultResultStatus
    ) -> [String] {
        evidence.outcomes
            .filter { $0.status == status }
            .map(\.faultID)
            .sorted()
    }

    private func compareIDs(
        _ actual: [String],
        _ expected: [String],
        label: String,
        mismatches: inout [String]
    ) {
        if actual != expected.sorted() {
            mismatches.append(
                label + " expected [" + expected.sorted().joined(separator: ",") + "], got [" + actual.joined(separator: ",") + "]"
            )
        }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }
}
