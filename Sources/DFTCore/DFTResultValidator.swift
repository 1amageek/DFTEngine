import CircuiteFoundation
import Foundation
import LogicIR

public struct DFTResultValidator: Sendable {
    public init() {}

    public func validate(
        _ result: DFTResult,
        for request: DFTRequest
    ) throws {
        guard result.schemaVersion == DFTRequest.currentSchemaVersion else {
            throw DFTResultValidationError.schemaVersionMismatch(
                expected: DFTRequest.currentSchemaVersion,
                actual: result.schemaVersion
            )
        }
        guard result.runID == request.runID else {
            throw DFTResultValidationError.runIDMismatch(
                expected: request.runID,
                actual: result.runID
            )
        }
        guard Set(result.provenance.inputs) == Set(request.executionInputArtifacts),
              result.provenance.inputs.count == request.executionInputArtifacts.count else {
            throw DFTResultValidationError.provenanceInputMismatch
        }
        let producer = result.provenance.producer
        guard !producer.identifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !producer.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              producer.build?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw DFTResultValidationError.producerIdentityIncomplete
        }
        try validateArtifacts(result.artifacts)
        if result.status == .completed {
            try validateCompletedPayload(
                result.payload,
                artifacts: Set(result.artifacts),
                for: request
            )
        }
    }

    private func validateArtifacts(_ artifacts: [ArtifactReference]) throws {
        guard Set(artifacts).count == artifacts.count else {
            throw DFTResultValidationError.artifactInvalid("references must be unique")
        }
        let artifactIDs = artifacts.map { $0.id.rawValue }
        guard Set(artifactIDs).count == artifactIDs.count else {
            throw DFTResultValidationError.artifactInvalid("artifact IDs must be unique")
        }
        let paths = artifacts.map(\.path)
        guard Set(paths).count == paths.count else {
            throw DFTResultValidationError.artifactInvalid("artifact paths must be unique")
        }
        for artifact in artifacts {
            let permitsEmptyLog = artifact.kind == .report && artifact.format == .raw
            guard (artifact.byteCount > 0 || permitsEmptyLog),
                  artifact.digest.algorithm == .sha256,
                  artifact.digest.hexadecimalValue.count == 64,
                  artifact.digest.hexadecimalValue.allSatisfy(\.isHexDigit) else {
                throw DFTResultValidationError.artifactInvalid(
                    "\(artifact.path) requires a non-empty SHA-256 identity"
                )
            }
        }
    }

    private func validateCompletedPayload(
        _ payload: DFTPayload,
        artifacts: Set<ArtifactReference>,
        for request: DFTRequest
    ) throws {
        switch request.operation {
        case .scanInsertion:
            guard let transformedDesign = payload.transformedDesign,
                  artifacts.contains(transformedDesign.artifact),
                  payload.scanPlan?.architecture == request.scanArchitecture,
                  request.insertionPolicy?.generateDesignDiff != true
                    || validateDesignDiff(
                        payload.designDiff,
                        transformedDesign: transformedDesign,
                        request: request
                    ) else {
                throw DFTResultValidationError.completedPayloadIncomplete(.scanInsertion)
            }
        case .atpg:
            guard let coverage = payload.faultCoverage,
                  let patterns = payload.patterns,
                  let evidence = payload.coverageEvidence,
                  !patterns.patterns.isEmpty else {
                throw DFTResultValidationError.completedPayloadIncomplete(.atpg)
            }
            try validateCoverage(
                coverage,
                patterns: patterns,
                evidence: evidence,
                request: request
            )
        case .bist:
            guard let transformedDesign = payload.transformedDesign,
                  artifacts.contains(transformedDesign.artifact),
                  let structure = payload.bistStructure,
                  validateDesignDiff(
                    payload.designDiff,
                    transformedDesign: transformedDesign,
                    request: request
                  ) else {
                throw DFTResultValidationError.completedPayloadIncomplete(.bist)
            }
            guard let configuration = request.bistConfiguration,
                  structure.kind == configuration.kind,
                  structure.controllerCellName == configuration.controllerCellName,
                  structure.targetInstances == configuration.targetInstances.sorted(),
                  structure.patternCount == configuration.patternCount,
                  structure.signatureRegisterName == configuration.signatureRegisterName else {
                throw DFTResultValidationError.completedPayloadIncomplete(.bist)
            }
            if configuration.kind == .logic {
                guard let mapping = configuration.logicCellMapping,
                      structure.logicCellMapping == mapping else {
                    throw DFTResultValidationError.completedPayloadIncomplete(.bist)
                }
            }
        }
    }

    private func validateCoverage(
        _ coverage: Double,
        patterns: DFTTestPatternSet,
        evidence: DFTCoverageEvidence,
        request: DFTRequest
    ) throws {
        guard let configuration = request.atpgConfiguration else {
            throw DFTResultValidationError.completedPayloadIncomplete(.atpg)
        }
        guard coverage.isFinite, (0...1).contains(coverage),
              evidence.coverage == coverage else {
            throw DFTResultValidationError.coverageInvalid(
                "reported coverage must be finite, normalized, and identical in the payload and evidence"
            )
        }
        let activeCount = evidence.declaredFaultCount - evidence.excludedFaultCount
        guard activeCount >= 0,
              evidence.detectedFaultCount + evidence.untestableFaultCount
                + evidence.abortedFaultCount == activeCount else {
            throw DFTResultValidationError.coverageInvalid(
                "fault outcome counts do not equal the active fault count"
            )
        }
        guard evidence.untestableFaultCount == 0,
              evidence.abortedFaultCount == 0 else {
            throw DFTResultValidationError.coverageInvalid(
                "completed ATPG results cannot retain untestable or aborted faults"
            )
        }
        let activeFaultIDs: Set<String>
        let universeDigest: String
        if let universe = request.faultUniverse {
            universeDigest = try DFTDeterministicHasher().digest(universe)
            let excludedFaultIDs = Set(universe.excludedFaultIDs)
            activeFaultIDs = Set(
                universe.faults.lazy
                    .map(\.id)
                    .filter { !excludedFaultIDs.contains($0) }
            )
            guard evidence.faultUniverseName == universe.name,
                  evidence.faultUniverseRevision == universe.revision,
                  evidence.declaredFaultCount == universe.faults.count,
                  evidence.excludedFaultCount == excludedFaultIDs.count else {
                throw DFTResultValidationError.coverageInvalid(
                    "coverage evidence must identify the requested fault universe"
                )
            }
        } else {
            guard configuration.faultSource == .gateLevel else {
                throw DFTResultValidationError.completedPayloadIncomplete(.atpg)
            }
            universeDigest = evidence.faultUniverseDigest
            activeFaultIDs = Set(evidence.outcomes.map(\.faultID))
        }
        guard universeDigest.count == 64,
              universeDigest.allSatisfy(\.isHexDigit),
              evidence.faultUniverseDigest == universeDigest,
              patterns.faultUniverseDigest == universeDigest,
              evidence.detectedFaultCount == activeFaultIDs.count,
              evidence.outcomes.count == activeFaultIDs.count,
              Set(evidence.outcomes.map(\.faultID)) == activeFaultIDs else {
            throw DFTResultValidationError.coverageInvalid(
                "coverage evidence must exactly identify every active requested fault"
            )
        }
        let expectedSeed = try configuration.randomSeed
            ?? DFTDeterministicHasher().seed(for: universeDigest)
        let patternIDs = patterns.patterns.map(\.id)
        guard patterns.format == configuration.patternFormat.rawValue,
              patterns.seed == expectedSeed,
              patterns.patterns.count <= configuration.maximumPatternCount,
              Set(patternIDs).count == patternIDs.count,
              patterns.patterns.allSatisfy({
                  $0.bits.count == configuration.patternLength
                      && !$0.faultIDs.isEmpty
                      && Set($0.faultIDs).isSubset(of: activeFaultIDs)
              }) else {
            throw DFTResultValidationError.coverageInvalid(
                "retained patterns must match the requested format, seed, size, and fault universe"
            )
        }
        let retainedPatternIDs = Set(patternIDs)
        let patternsByID = Dictionary(
            uniqueKeysWithValues: patterns.patterns.map { ($0.id, $0) }
        )
        guard evidence.outcomes.allSatisfy({
            $0.status == .detected
                && $0.patternID.map(retainedPatternIDs.contains) == true
                && $0.patternID.flatMap { patternsByID[$0] }?.faultIDs.contains($0.faultID) == true
        }) else {
            throw DFTResultValidationError.coverageInvalid(
                "every completed fault outcome must reference a retained detecting pattern"
            )
        }
        guard activeFaultIDs.isEmpty == false,
              coverage == Double(evidence.detectedFaultCount) / Double(activeFaultIDs.count) else {
            throw DFTResultValidationError.coverageInvalid(
                "completed ATPG coverage must equal the detected-to-active fault ratio"
            )
        }
    }

    private func validateDesignDiff(
        _ diff: DFTDesignDiff?,
        transformedDesign: LogicDesignReference,
        request: DFTRequest
    ) -> Bool {
        guard let diff else {
            return false
        }
        return diff.runID == request.runID
            && diff.baseSnapshot == request.design.artifact
            && diff.proposedSnapshot == transformedDesign.artifact
            && !diff.changes.isEmpty
    }
}
