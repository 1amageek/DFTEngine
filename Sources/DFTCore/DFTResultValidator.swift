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
                  let scanPlan = payload.scanPlan,
                  validateScanPlan(scanPlan, request: request),
                  let scanImplementation = payload.scanImplementation,
                  validateScanImplementation(
                    scanImplementation,
                    transformedDesign: transformedDesign,
                    plan: scanPlan,
                    artifacts: artifacts,
                    request: request
                  ),
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
            if let scanImplementation = request.scanImplementation {
                guard let executionPlan = payload.scanPatternExecutionPlan,
                      validateScanPatternExecutionPlan(
                          executionPlan,
                          scanImplementation: scanImplementation,
                          patterns: patterns,
                          artifacts: artifacts,
                          request: request
                      ) else {
                    throw DFTResultValidationError.completedPayloadIncomplete(.atpg)
                }
            } else if payload.scanPatternExecutionPlan != nil {
                throw DFTResultValidationError.completedPayloadIncomplete(.atpg)
            }
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
            guard let configuration = request.bistConfiguration else {
                throw DFTResultValidationError.completedPayloadIncomplete(.bist)
            }
            let expectedSeed = try expectedBISTSeed(configuration, request: request)
            guard
                  structure.name == configuration.name,
                  structure.kind == configuration.kind,
                  structure.controllerCellName == configuration.controllerCellName,
                  structure.targetInstances == configuration.targetInstances.sorted(),
                  structure.patternCount == configuration.patternCount,
                  structure.signatureRegisterName == configuration.signatureRegisterName,
                  structure.seed == expectedSeed,
                  structure.testModeSignal == expectedBISTTestModeSignal(
                      configuration,
                      request: request
                  ) else {
                throw DFTResultValidationError.completedPayloadIncomplete(.bist)
            }
            if configuration.kind == .logic {
                guard let mapping = configuration.logicCellMapping,
                      structure.logicCellMapping == mapping,
                      structure.memoryBindings == nil else {
                    throw DFTResultValidationError.completedPayloadIncomplete(.bist)
                }
            } else {
                guard structure.logicCellMapping == nil,
                      structure.memoryBindings == configuration.memoryBindings else {
                    throw DFTResultValidationError.completedPayloadIncomplete(.bist)
                }
            }
        }
    }

    private func validateScanImplementation(
        _ implementation: DFTScanImplementation,
        transformedDesign: LogicDesignReference,
        plan: DFTScanPlan,
        artifacts: Set<ArtifactReference>,
        request: DFTRequest
    ) -> Bool {
        guard let architecture = request.scanArchitecture,
              DFTScanImplementationValidator()
                .validationIssues(in: implementation).isEmpty,
              implementation.schemaVersion
                == DFTScanImplementation.currentSchemaVersion,
              implementation.architectureName == architecture.name,
              implementation.sourceDesignDigest == request.design.designDigest,
              implementation.transformedDesignDigest
                == transformedDesign.designDigest,
              implementation.scanEnableSignal == architecture.scanEnableSignal,
              implementation.testModeSignal == architecture.testModeSignal,
              !implementation.scanEnableNetID.isEmpty,
              !implementation.testModeNetID.isEmpty,
              implementation.chains.count == plan.chains.count,
              artifacts.contains(where: {
                  $0.id.rawValue == "dft-scan-implementation"
                    && $0.kind == .report
                    && $0.format == .json
              }) else {
            return false
        }
        let plannedByID = Dictionary(
            uniqueKeysWithValues: plan.chains.map { ($0.id, $0) }
        )
        var cellIDs = Set<String>()
        return implementation.chains.allSatisfy { chain in
            guard let planned = plannedByID[chain.chainID],
                  chain.domainID == planned.domainID,
                  chain.scanInSignal == planned.scanInSignal,
                  chain.scanOutSignal == planned.scanOutSignal,
                  chain.elements.count == planned.estimatedElementCount,
                  !chain.scanInNetID.isEmpty,
                  !chain.scanOutNetID.isEmpty,
                  chain.elements.indices.allSatisfy({
                      chain.elements[$0].position == $0
                  }),
                  chain.elements.first?.scanInNetID == chain.scanInNetID,
                  chain.elements.last?.outputNetID == chain.scanOutNetID else {
                return false
            }
            for (index, element) in chain.elements.enumerated() {
                guard cellIDs.insert(element.cellID).inserted,
                      !element.instanceName.isEmpty,
                      !element.cellType.isEmpty,
                      !element.dataNetID.isEmpty,
                      !element.outputNetID.isEmpty,
                      !element.clockNetID.isEmpty,
                      element.scanEnableNetID
                        == implementation.scanEnableNetID,
                      element.testModePinName == nil
                        ? element.testModeNetID == nil
                        : element.testModeNetID
                            == implementation.testModeNetID else {
                    return false
                }
                if index > 0,
                   chain.elements[index - 1].outputNetID
                    != element.scanInNetID {
                    return false
                }
            }
            return true
        }
    }

    private func validateScanPlan(
        _ plan: DFTScanPlan,
        request: DFTRequest
    ) -> Bool {
        guard let architecture = request.scanArchitecture,
              plan.architecture == architecture,
              !plan.chains.isEmpty,
              Set(plan.chains.map(\.id)).count == plan.chains.count,
              plan.totalEstimatedElementCount
                == plan.chains.reduce(0, { $0 + $1.estimatedElementCount }),
              plan.maximumEstimatedChainLength
                == plan.chains.map(\.estimatedElementCount).max() else {
            return false
        }
        return architecture.domains.allSatisfy { domain in
            let chains = plan.chains.filter { $0.domainID == domain.id }
            return chains.count == domain.chainCount
                && chains.reduce(0, { $0 + $1.estimatedElementCount })
                    == domain.estimatedElementCount
        }
    }

    private func expectedBISTSeed(
        _ configuration: DFTBISTConfiguration,
        request: DFTRequest
    ) throws -> UInt64 {
        if let randomSeed = configuration.randomSeed {
            return randomSeed
        }
        return try DFTDeterministicHasher().seed(
            for: "\(request.design.designDigest):\(configuration.name)"
        )
    }

    private func expectedBISTTestModeSignal(
        _ configuration: DFTBISTConfiguration,
        request: DFTRequest
    ) -> String? {
        configuration.testModeSignal
            ?? request.testIntent?.testModeSignal
            ?? request.scanArchitecture?.testModeSignal
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
        if let universe = request.faultUniverse {
            let processFaultIDs = Set(
                universe.faults.lazy
                    .filter { $0.family == .processSpecific }
                    .map(\.id)
            ).intersection(activeFaultIDs)
            let outcomesByFaultID = Dictionary(
                uniqueKeysWithValues: evidence.outcomes.map {
                    ($0.faultID, $0)
                }
            )
            for faultID in processFaultIDs {
                guard let outcome = outcomesByFaultID[faultID],
                      let modelID = outcome.modelID,
                      !modelID.isEmpty,
                      let verificationID = outcome.verificationID,
                      !verificationID.isEmpty,
                      verificationID != modelID,
                      let timing = outcome.processCaptureTiming else {
                    throw DFTResultValidationError.coverageInvalid(
                        "process fault \(faultID) requires distinct model/verifier identities and retained capture timing"
                    )
                }
                do {
                    try DFTProcessCaptureTimingValidator().validate(
                        timing,
                        architecture: request.scanArchitecture
                    )
                } catch {
                    throw DFTResultValidationError.coverageInvalid(
                        "process fault \(faultID) has invalid capture timing: \(error.localizedDescription)"
                    )
                }
            }
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

    private func validateScanPatternExecutionPlan(
        _ plan: DFTScanPatternExecutionPlan,
        scanImplementation: DFTScanImplementationReference,
        patterns: DFTTestPatternSet,
        artifacts: Set<ArtifactReference>,
        request: DFTRequest
    ) -> Bool {
        guard let architecture = request.scanArchitecture,
              plan.schemaVersion
                == DFTScanPatternExecutionPlan.currentSchemaVersion,
              plan.scanImplementationDigest.caseInsensitiveCompare(
                  scanImplementation.artifact.digest.hexadecimalValue
              ) == .orderedSame,
              plan.transformedDesignDigest
                == scanImplementation.transformedDesignDigest,
              !plan.clockSignal.isEmpty,
              plan.clockPeriodPicoseconds > 0,
              plan.scanEnableSignal == architecture.scanEnableSignal,
              plan.testModeSignal == architecture.testModeSignal,
              artifacts.contains(where: {
                  $0.id.rawValue == "dft-scan-pattern-execution-plan"
                    && $0.kind == .testPattern
                    && $0.format == .json
              }),
              !plan.patterns.isEmpty,
              plan.patterns.count == patterns.patterns.count,
              Set(plan.patterns.map(\.id)).count == plan.patterns.count,
              Set(plan.patterns.map(\.id))
                == Set(patterns.patterns.map(\.id)) else {
            return false
        }
        let patternsByID = Dictionary(
            uniqueKeysWithValues: patterns.patterns.map { ($0.id, $0) }
        )
        return plan.patterns.allSatisfy { execution in
            guard let pattern = patternsByID[execution.id],
                  !execution.faultIDs.isEmpty,
                  Set(execution.faultIDs).count == execution.faultIDs.count,
                  Set(execution.faultIDs) == Set(pattern.faultIDs),
                  !execution.chains.isEmpty,
                  Set(execution.chains.map(\.chainID)).count
                    == execution.chains.count,
                  execution.capture.primaryInputs[plan.clockSignal] == true,
                  execution.capture.primaryInputs[plan.scanEnableSignal]
                    == false,
                  execution.capture.primaryInputs[plan.testModeSignal]
                    == true else {
                return false
            }
            var outputNetIDs = Set<String>()
            return execution.chains.allSatisfy { chain in
                !chain.chainID.isEmpty
                    && !chain.scanInSignal.isEmpty
                    && !chain.scanOutSignal.isEmpty
                    && !chain.elementOutputNetIDs.isEmpty
                    && chain.loadBits.count
                        == chain.elementOutputNetIDs.count
                    && chain.expectedUnloadBits.count
                        == chain.elementOutputNetIDs.count
                    && chain.loadBits.allSatisfy({
                        $0 == "0" || $0 == "1"
                    })
                    && chain.expectedUnloadBits.allSatisfy({
                        $0 == "0" || $0 == "1"
                    })
                    && chain.elementOutputNetIDs.allSatisfy {
                        !$0.isEmpty && outputNetIDs.insert($0).inserted
                    }
            }
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
