import CircuiteFoundation
import Foundation
import DFTCore
import LogicIR
import PDKCore

public struct DeterministicATPGEngine: ATPGExecuting {
    public let artifactStore: any DFTArtifactStoring
    public let designLoader: (any DFTDesignLoading)?
    public let cellLibraryLoader: (any DFTCellLibraryLoading)?
    public let timingLibraryLoader: (any DFTTimingLibraryLoading)?
    public let constraintLoader: any DFTConstraintLoading
    public let scanImplementationLoader: (any DFTScanImplementationLoading)?
    public let realizedScanSearcher: any RealizedScanATPGSearching
    public let faultExtractor: any DFTFaultExtracting
    public let simulator: any GateLevelSimulating
    public let sequentialSimulator: any GateLevelSequentialSimulating
    public let transitionSimulator: any GateLevelTransitionSimulating
    public let processFaultModel: (any DFTProcessFaultModeling)?
    public let processFaultPatternVerifier: (any DFTProcessFaultPatternVerifying)?
    public let implementationID: String

    public init(
        artifactStore: any DFTArtifactStoring = InMemoryDFTArtifactStore(),
        designLoader: (any DFTDesignLoading)? = nil,
        cellLibraryLoader: (any DFTCellLibraryLoading)? = nil,
        timingLibraryLoader: (any DFTTimingLibraryLoading)? = nil,
        constraintLoader: any DFTConstraintLoading = UnavailableDFTConstraintLoader(),
        scanImplementationLoader: (any DFTScanImplementationLoading)? = nil,
        realizedScanSearcher: any RealizedScanATPGSearching =
            ExhaustiveRealizedScanATPGSearcher(),
        faultExtractor: any DFTFaultExtracting = GateLevelFaultExtractor(),
        simulator: any GateLevelSimulating = GateLevelCombinationalSimulator(),
        sequentialSimulator: any GateLevelSequentialSimulating = GateLevelSequentialSimulator(),
        transitionSimulator: any GateLevelTransitionSimulating = GateLevelTransitionSimulator(),
        processFaultModel: (any DFTProcessFaultModeling)? = nil,
        processFaultPatternVerifier: (any DFTProcessFaultPatternVerifying)? = nil,
        implementationID: String = "native-deterministic-atpg"
    ) {
        self.artifactStore = artifactStore
        self.designLoader = designLoader
        self.cellLibraryLoader = cellLibraryLoader
        self.timingLibraryLoader = timingLibraryLoader
        self.constraintLoader = constraintLoader
        if let scanImplementationLoader {
            self.scanImplementationLoader = scanImplementationLoader
        } else if let artifactReader = artifactStore as? any DFTArtifactReading {
            self.scanImplementationLoader = VerifiedDFTScanImplementationLoader(
                artifactReader: artifactReader
            )
        } else {
            self.scanImplementationLoader = nil
        }
        self.realizedScanSearcher = realizedScanSearcher
        self.faultExtractor = faultExtractor
        self.simulator = simulator
        self.sequentialSimulator = sequentialSimulator
        self.transitionSimulator = transitionSimulator
        self.processFaultModel = processFaultModel
        self.processFaultPatternVerifier = processFaultPatternVerifier
        self.implementationID = implementationID
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        let startedAt = Date()
        let engineID = "dft.atpg"
        do {
            try Task.checkCancellation()
            let issues = request.validationIssues(for: .atpg)
            guard issues.isEmpty else {
                return try DFTExecutionSupport.result(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    status: .blocked,
                    diagnostics: DFTExecutionSupport.diagnostics(for: issues),
                    payload: DFTPayload(
                        transformedDesign: nil,
                        faultCoverage: nil,
                        evidenceProvenance: evidenceProvenance,
                        assumptions: ["coverage was not reported because the fault universe or ATPG prerequisites are invalid"]
                    ),
                    startedAt: startedAt
                )
            }
            guard var configuration = request.atpgConfiguration else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_ATPG_PREREQUISITE_MISSING",
                    message: "Fault universe and ATPG configuration are required."
                )
            }
            guard configuration.patternFormat == .json else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_PATTERN_FORMAT_UNSUPPORTED",
                    message: "Native ATPG persists canonical JSON patterns; STIL and WGL require a qualified external codec.",
                    entity: "atpgConfiguration.patternFormat",
                    actions: [
                        "select_json_pattern_format",
                        "inject_a_qualified_external_pattern_codec",
                    ]
                )
            }
            do {
                try DFTConstraintValidator().validate(
                    constraintLoader.load(request.constraints),
                    request: request
                )
            } catch {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_CONSTRAINT_VALIDATION_FAILED",
                    message: error.localizedDescription,
                    entity: request.constraints.artifacts.first?.path ?? "constraints",
                    actions: ["provide_constraint_loader", "repair_test_mode_constraints"]
                )
            }
            if configuration.maximumPatternCount <= 0 || configuration.patternLength <= 0 || configuration.abortLimit < 0 {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_ATPG_CONFIGURATION_INVALID",
                    message: "ATPG pattern count and length must be positive and abort limit cannot be negative.",
                    entity: "atpgConfiguration",
                    actions: ["provide_positive_atpg_limits"]
                )
            }

            if let cellLibraryReference = request.cellLibrary {
                guard let cellLibraryLoader else {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_CELL_LIBRARY_LOADER_MISSING",
                        message: "ATPG cannot use a process-scoped cell library without a manifest loader.",
                        entity: cellLibraryReference.artifact.path,
                        actions: ["provide_cell_library_loader", "persist_cell_library_manifest"]
                    )
                }
                let manifest: DFTCellLibraryManifest
                do {
                    manifest = try cellLibraryLoader.load(cellLibraryReference)
                    try validate(cellLibrary: manifest, reference: cellLibraryReference, pdk: request.pdk)
                    guard let timingReference = cellLibraryReference.timingLibraryArtifact,
                          let timingLibraryLoader else {
                        throw DFTCellLibraryTimingError.timingCellMissing(
                            bindingID: "<all>",
                            cellName: "<timing-library>"
                        )
                    }
                    let timingLibrary = try timingLibraryLoader.load(timingReference)
                    _ = try DFTCellLibraryTimingValidator().validate(
                        manifest: manifest,
                        timingLibrary: timingLibrary
                    )
                } catch {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_CELL_LIBRARY_LOAD_FAILED",
                        message: error.localizedDescription,
                        entity: cellLibraryReference.artifact.path,
                        actions: ["verify_cell_library_digest", "align_cell_library_with_pdk", "attach_qualification_evidence"]
                    )
                }
                configuration = configuration.replacingSequentialCellContracts(
                    manifest.bindings.map(\.sequentialCellContract)
                )
            }

            let faultSource = configuration.faultSource ?? .declaredUniverse
            let universe: DFTFaultUniverse
            let gateSnapshot: LogicDesignSnapshot?
            switch faultSource {
            case .declaredUniverse:
                guard let declaredUniverse = request.faultUniverse else {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_FAULT_UNIVERSE_MISSING",
                        message: "Declared-universe ATPG requires a fault universe.",
                        entity: "faultUniverse",
                        actions: ["declare_fault_universe", "select_gate_level_fault_source"]
                    )
                }
                universe = declaredUniverse
                gateSnapshot = nil
            case .gateLevel:
                guard let designLoader else {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_DESIGN_LOADER_MISSING",
                        message: "Gate-level ATPG requires a canonical LogicDesignSnapshot loader.",
                        entity: "design",
                        actions: ["inject_design_loader", "provide_gate_level_design_artifact"]
                    )
                }
                let loadedSnapshot: LogicDesignSnapshot
                do {
                    loadedSnapshot = try designLoader.load(request.design)
                } catch {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_DESIGN_LOAD_FAILED",
                        message: "Could not load the canonical design for gate-level ATPG: \(error.localizedDescription)",
                        entity: request.design.artifact.path,
                        actions: ["verify_design_artifact_integrity", "repair_gate_level_snapshot"]
                    )
                }
                do {
                    universe = try faultExtractor.extract(
                        from: loadedSnapshot,
                        reference: request.design
                    )
                } catch {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_FAULT_EXTRACTION_FAILED",
                        message: "Could not derive a gate-level fault universe: \(error.localizedDescription)",
                        entity: request.design.artifact.path,
                        actions: ["repair_gate_connectivity", "use_declared_fault_universe"]
                    )
                }
                gateSnapshot = loadedSnapshot
            }

            let universeDigest = try DFTDeterministicHasher().digest(universe)
            let seed = try configuration.randomSeed ?? DFTDeterministicHasher().seed(for: universeDigest)
            let excluded = Set(universe.excludedFaultIDs)
            let activeFaults = universe.faults
                .filter { !excluded.contains($0.id) }
                .sorted { $0.id < $1.id }

            var outcomes: [DFTFaultOutcome] = []
            var patterns: [DFTTestPattern] = []
            var diagnostics: [DFTDiagnostic] = []
            var scanPatternExecutionPlan: DFTScanPatternExecutionPlan?
            var declaredGateSnapshot: LogicDesignSnapshot?
            var abortedCount = 0
            var untestableCount = 0
            if faultSource == .declaredUniverse,
               activeFaults.contains(where: {
                   $0.family == .stuckAt || $0.family == .transition
               }),
               let designLoader {
                do {
                    declaredGateSnapshot = try designLoader.load(request.design)
                } catch {
                    diagnostics.append(DFTDiagnostic(
                        severity: .error,
                        code: "DFT_DECLARED_FAULT_DESIGN_LOAD_FAILED",
                        message: "Declared-fault ATPG could not load the canonical design: \(error.localizedDescription)",
                        entity: request.design.artifact.path,
                        suggestedActions: ["verify_design_artifact_integrity", "provide_a_qualified_fault_model"]
                    ))
                }
            }
            if faultSource == .gateLevel {
                guard let gateSnapshot else {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_GATE_LEVEL_SNAPSHOT_MISSING",
                        message: "Gate-level ATPG could not retain the loaded canonical design.",
                        entity: "design"
                    )
                }
                do {
                    let search: GateLevelATPGSearchResult
                    if let scanReference = request.scanImplementation {
                        guard let scanImplementationLoader else {
                            return try blocked(
                                request: request,
                                engineID: engineID,
                                startedAt: startedAt,
                                code: "DFT_SCAN_IMPLEMENTATION_LOADER_MISSING",
                                message: "Scan-pattern ATPG requires a digest-verifying scan implementation loader.",
                                entity: scanReference.artifact.path,
                                actions: ["inject_scan_implementation_loader"]
                            )
                        }
                        let implementation: DFTScanImplementation
                        do {
                            implementation = try await scanImplementationLoader
                                .load(scanReference)
                        } catch {
                            return try blocked(
                                request: request,
                                engineID: engineID,
                                startedAt: startedAt,
                                code: "DFT_SCAN_IMPLEMENTATION_LOAD_FAILED",
                                message: error.localizedDescription,
                                entity: scanReference.artifact.path,
                                actions: [
                                    "verify_scan_implementation_digest",
                                    "bind_atpg_to_the_transformed_design",
                                ]
                            )
                        }
                        let scanSearch = try realizedScanSearcher.search(
                            snapshot: gateSnapshot,
                            faults: activeFaults,
                            configuration: configuration,
                            architecture: request.scanArchitecture,
                            implementation: implementation,
                            implementationDigest: scanReference.artifact.digest
                                .hexadecimalValue,
                            sequentialSimulator: sequentialSimulator
                        )
                        search = GateLevelATPGSearchResult(
                            outcomes: scanSearch.outcomes,
                            patterns: scanSearch.patterns,
                            diagnostics: scanSearch.diagnostics,
                            abortedCount: scanSearch.abortedCount,
                            untestableCount: scanSearch.untestableCount
                        )
                        scanPatternExecutionPlan = scanSearch.executionPlan
                    } else {
                        search = try searchGateLevel(
                            snapshot: gateSnapshot,
                            faults: activeFaults,
                            configuration: configuration,
                            sequentialSimulator: sequentialSimulator
                        )
                    }
                    outcomes = search.outcomes
                    patterns = search.patterns
                    diagnostics.append(contentsOf: search.diagnostics)
                    abortedCount = search.abortedCount
                    untestableCount = search.untestableCount
                } catch let error as GateLevelATPGError {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_GATE_LEVEL_ATPG_BLOCKED",
                        message: error.localizedDescription,
                        entity: "faultUniverse",
                        actions: ["reduce_primary_input_width", "increase_pattern_length", "qualify_supported_gate_cells"]
                    )
                } catch let error as GateLevelSimulationError {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_GATE_LEVEL_SIMULATION_BLOCKED",
                        message: error.localizedDescription,
                        entity: "faultUniverse",
                        actions: ["qualify_gate_cell_semantics", "repair_gate_connectivity", "use_declared_fault_universe"]
                    )
                } catch {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_GATE_LEVEL_ATPG_FAILED",
                        message: "Gate-level ATPG failed: \(error.localizedDescription)",
                        entity: "faultUniverse"
                    )
                }
            } else {
              for (index, fault) in activeFaults.enumerated() {
                try Task.checkCancellation()
                if index >= configuration.maximumPatternCount {
                    abortedCount += 1
                    outcomes.append(DFTFaultOutcome(
                        faultID: fault.id,
                        status: .aborted,
                        reason: "pattern budget exhausted"
                    ))
                    continue
                }
                if fault.location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    untestableCount += 1
                    outcomes.append(DFTFaultOutcome(
                        faultID: fault.id,
                        status: .untestable,
                        reason: "fault location is unavailable"
                    ))
                    diagnostics.append(DFTDiagnostic(
                        severity: .error,
                        code: "DFT_FAULT_LOCATION_MISSING",
                        message: "Fault \(fault.id) cannot be modeled without a location.",
                        entity: fault.id,
                        suggestedActions: ["declare_fault_location"]
                    ))
                    continue
                }
                if fault.family == .transition {
                    guard let declaredGateSnapshot,
                          fault.transitionDirection != nil else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: "transition direction or canonical combinational design is unavailable"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_FAULT_SEMANTICS_UNAVAILABLE",
                            message: "Transition fault \(fault.id) requires an explicit direction and a canonical combinational design.",
                            entity: fault.id,
                            suggestedActions: ["declare_transition_direction", "inject_design_loader", "use_a_qualified_transition_backend"]
                        ))
                        continue
                    }
                    do {
                        guard let bits = try searchTransitionFault(
                            snapshot: declaredGateSnapshot,
                            fault: fault,
                            configuration: configuration
                        ) else {
                            untestableCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .untestable,
                                reason: "no bounded launch/capture input pair changed an observable output"
                            ))
                            continue
                        }
                        let patternID = "pattern-\(patterns.count + 1)"
                        patterns.append(DFTTestPattern(
                            id: patternID,
                            bits: bits,
                            faultIDs: [fault.id]
                        ))
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .detected,
                            patternID: patternID,
                            reason: "detected by bounded combinational launch/capture simulation"
                        ))
                    } catch let error as GateLevelATPGError {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: error.localizedDescription
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_FAULT_SEMANTICS_UNAVAILABLE",
                            message: error.localizedDescription,
                            entity: fault.id,
                            suggestedActions: ["reduce_transition_vector_width", "use_a_qualified_transition_backend"]
                        ))
                    } catch let error as GateLevelSimulationError {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: error.localizedDescription
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_FAULT_SEMANTICS_UNAVAILABLE",
                            message: error.localizedDescription,
                            entity: fault.id,
                            suggestedActions: ["qualify_combinational_transition_semantics", "use_a_declared_fault_model"]
                        ))
                    }
                    continue
                }
                if fault.family == .stuckAt {
                    guard let declaredGateSnapshot else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: "canonical gate design is unavailable for declared stuck-at fault simulation"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_DECLARED_FAULT_DESIGN_MISSING",
                            message: "Declared stuck-at fault \(fault.id) requires a canonical gate design and independent fault simulation.",
                            entity: fault.id,
                            suggestedActions: ["inject_design_loader", "select_gate_level_fault_source"]
                        ))
                        continue
                    }
                    do {
                        let search = try searchGateLevel(
                            snapshot: declaredGateSnapshot,
                            faults: [fault],
                            configuration: configuration,
                            sequentialSimulator: sequentialSimulator
                        )
                        guard let evaluatedOutcome = search.outcomes.first else {
                            throw GateLevelATPGError.simulationFailed(
                                faultID: fault.id,
                                message: "fault simulation produced no outcome"
                            )
                        }
                        diagnostics.append(contentsOf: search.diagnostics.filter {
                            $0.severity != .info
                        })
                        switch evaluatedOutcome.status {
                        case .detected:
                            guard let detectedPattern = search.patterns.first else {
                                throw GateLevelATPGError.simulationFailed(
                                    faultID: fault.id,
                                    message: "detected fault has no retained pattern"
                                )
                            }
                            let patternID = "pattern-\(patterns.count + 1)"
                            patterns.append(DFTTestPattern(
                                id: patternID,
                                bits: detectedPattern.bits,
                                faultIDs: [fault.id]
                            ))
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .detected,
                                patternID: patternID,
                                reason: "detected by canonical gate-level fault simulation"
                            ))
                        case .untestable:
                            untestableCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .untestable,
                                reason: evaluatedOutcome.reason
                            ))
                        case .aborted:
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                reason: evaluatedOutcome.reason
                            ))
                        }
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: error.localizedDescription
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_DECLARED_FAULT_SIMULATION_FAILED",
                            message: "Declared stuck-at fault \(fault.id) could not be validated: \(error.localizedDescription)",
                            entity: fault.id,
                            suggestedActions: ["repair_fault_location", "verify_gate_semantics"]
                        ))
                    }
                    continue
                }
                if fault.family == .processSpecific {
                    guard let processFamily = fault.processFamily,
                          configuration.supportedProcessFamilies.contains(processFamily) else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: "process fault family is not declared in the ATPG configuration"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_PROCESS_FAULT_FAMILY_UNDECLARED",
                            message: "ATPG cannot evaluate process-specific fault \(fault.id) without a declared process family.",
                            entity: fault.id,
                            suggestedActions: ["declare_process_fault_family", "inject_a_qualified_process_fault_model"]
                        ))
                        continue
                    }
                    guard let processFaultModel else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            reason: "no process-specific fault model was injected"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_PROCESS_FAULT_MODEL_MISSING",
                            message: "Process-specific fault \(fault.id) requires an injected and separately qualified fault model.",
                            entity: fault.id,
                            suggestedActions: ["inject_a_qualified_process_fault_model", "use_a_supported_fault_family"]
                        ))
                        continue
                    }
                    guard processFaultModel.supports(processFamily: processFamily) else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            modelID: processFaultModel.modelID,
                            reason: "injected process-specific fault model does not support the declared family"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_PROCESS_FAULT_MODEL_UNSUPPORTED",
                            message: "Injected process fault model \(processFaultModel.modelID) does not support family \(processFamily).",
                            entity: fault.id,
                            suggestedActions: ["select_a_model_for_the_process_family", "use_a_supported_fault_family"]
                        ))
                        continue
                    }
                    let modelResult: DFTProcessFaultModelResult
                    do {
                        modelResult = try await processFaultModel.evaluate(
                            fault: fault,
                            request: request,
                            configuration: configuration
                        )
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            modelID: processFaultModel.modelID,
                            reason: "process fault model failed: \(error.localizedDescription)"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_PROCESS_FAULT_MODEL_FAILED",
                            message: "Process fault model \(processFaultModel.modelID) failed for \(fault.id): \(error.localizedDescription)",
                            entity: fault.id,
                            suggestedActions: ["inspect_process_fault_model_diagnostics", "retain_model_failure_artifact"]
                        ))
                        continue
                    }
                    guard modelResult.modelID == processFaultModel.modelID,
                          !modelResult.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            modelID: processFaultModel.modelID,
                            reason: "process fault model returned an invalid result identity"
                        ))
                        diagnostics.append(DFTDiagnostic(
                            severity: .error,
                            code: "DFT_PROCESS_FAULT_MODEL_INVALID_RESULT",
                            message: "Process fault model returned an invalid identity or empty reason for \(fault.id).",
                            entity: fault.id,
                            suggestedActions: ["repair_process_fault_model_result"]
                        ))
                        continue
                    }
                    switch modelResult.status {
                    case .detected:
                        guard let patternBits = modelResult.patternBits,
                              patternBits.count == configuration.patternLength,
                              patternBits.allSatisfy({ $0 == "0" || $0 == "1" }) else {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                reason: "process fault model returned an invalid detected pattern"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_MODEL_INVALID_PATTERN",
                                message: "Process fault model returned a non-binary pattern with the wrong length for \(fault.id).",
                                entity: fault.id,
                                suggestedActions: ["repair_process_fault_pattern", "align_pattern_length"]
                            ))
                            continue
                        }
                        guard let captureTiming = modelResult.captureTiming else {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                reason: "process fault model returned invalid or unbound capture timing"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_CAPTURE_TIMING_INVALID",
                                message: "Process fault model returned capture timing that is not bound to a declared DFT clock for \(fault.id).",
                                entity: fault.id,
                                suggestedActions: ["bind_process_capture_timing", "repair_process_fault_model_result"]
                            ))
                            continue
                        }
                        do {
                            try DFTProcessCaptureTimingValidator().validate(
                                captureTiming,
                                architecture: request.scanArchitecture
                            )
                        } catch {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                processCaptureTiming: captureTiming,
                                reason: "process fault capture timing validation failed: \(error.localizedDescription)"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_CAPTURE_TIMING_INVALID",
                                message: "Process fault model returned invalid capture timing for \(fault.id): \(error.localizedDescription)",
                                entity: fault.id,
                                suggestedActions: ["bind_process_capture_timing", "repair_process_fault_model_result"]
                            ))
                            continue
                        }
                        guard let processFaultPatternVerifier,
                              !processFaultPatternVerifier.verifierID.isEmpty,
                              processFaultPatternVerifier.verifierID
                                != processFaultModel.modelID else {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                processCaptureTiming: captureTiming,
                                reason: "no independent process fault pattern verifier was injected"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_PATTERN_VERIFIER_MISSING",
                                message: "Detected process fault \(fault.id) requires a non-self verifier with a distinct identity.",
                                entity: fault.id,
                                suggestedActions: ["inject_independent_process_pattern_verifier"]
                            ))
                            continue
                        }
                        let isPatternValid: Bool
                        do {
                            isPatternValid = try await processFaultPatternVerifier.validate(
                                result: modelResult,
                                fault: fault,
                                request: request,
                                configuration: configuration
                            )
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                verificationID: processFaultPatternVerifier.verifierID,
                                processCaptureTiming: captureTiming,
                                reason: "process fault pattern verification failed: \(error.localizedDescription)"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_PATTERN_VERIFICATION_FAILED",
                                message: "Independent process pattern verifier \(processFaultPatternVerifier.verifierID) failed for \(fault.id): \(error.localizedDescription)",
                                entity: fault.id,
                                suggestedActions: ["inspect_process_pattern_verifier_evidence"]
                            ))
                            continue
                        }
                        guard isPatternValid else {
                            abortedCount += 1
                            outcomes.append(DFTFaultOutcome(
                                faultID: fault.id,
                                status: .aborted,
                                modelID: processFaultModel.modelID,
                                verificationID: processFaultPatternVerifier.verifierID,
                                processCaptureTiming: captureTiming,
                                reason: "independent process fault pattern verification rejected the result"
                            ))
                            diagnostics.append(DFTDiagnostic(
                                severity: .error,
                                code: "DFT_PROCESS_FAULT_PATTERN_REJECTED",
                                message: "Independent process pattern verifier \(processFaultPatternVerifier.verifierID) rejected \(fault.id).",
                                entity: fault.id,
                                suggestedActions: ["repair_process_fault_pattern", "inspect_process_model_disagreement"]
                            ))
                            continue
                        }
                        let patternID = "pattern-\(patterns.count + 1)"
                        patterns.append(DFTTestPattern(
                            id: patternID,
                            bits: patternBits,
                            faultIDs: [fault.id]
                        ))
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .detected,
                            patternID: patternID,
                            modelID: modelResult.modelID,
                            verificationID: processFaultPatternVerifier.verifierID,
                            processCaptureTiming: captureTiming,
                            reason: "detected by process fault model \(modelResult.modelID): \(modelResult.reason)"
                        ))
                    case .untestable:
                        untestableCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .untestable,
                            modelID: modelResult.modelID,
                            reason: modelResult.reason
                        ))
                    case .aborted:
                        abortedCount += 1
                        outcomes.append(DFTFaultOutcome(
                            faultID: fault.id,
                            status: .aborted,
                            modelID: modelResult.modelID,
                            reason: modelResult.reason
                        ))
                    }
                    continue
                }
                guard supports(fault: fault, configuration: configuration) else {
                    abortedCount += 1
                    outcomes.append(DFTFaultOutcome(
                        faultID: fault.id,
                        status: .aborted,
                        reason: "fault family semantics are unavailable to this backend"
                    ))
                    diagnostics.append(DFTDiagnostic(
                        severity: .error,
                        code: "DFT_FAULT_SEMANTICS_UNAVAILABLE",
                        message: "ATPG was blocked for fault \(fault.id) because no declared backend model is available for family \(fault.family.rawValue).",
                        entity: fault.id,
                        suggestedActions: ["provide_qualified_process_fault_model"]
                    ))
                    continue
                }
                abortedCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .aborted,
                    reason: "fault semantics require a canonical simulator or an injected qualified model"
                ))
                diagnostics.append(DFTDiagnostic(
                    severity: .error,
                    code: "DFT_FAULT_SIMULATOR_MISSING",
                    message: "Fault \(fault.id) cannot be marked detected without an independently replayable simulation.",
                    entity: fault.id,
                    suggestedActions: ["provide_canonical_fault_simulator", "inject_a_qualified_fault_model"]
                ))
              }
            }

            let detectedCount = outcomes.filter { $0.status == .detected }.count
            let denominator = activeFaults.count
            let coverage: Double? = abortedCount > configuration.abortLimit || untestableCount > 0
                ? nil
                : (denominator == 0 ? nil : Double(detectedCount) / Double(denominator))
            let evidence = DFTCoverageEvidence(
                faultUniverseName: universe.name,
                faultUniverseRevision: universe.revision,
                faultUniverseDigest: universeDigest,
                declaredFaultCount: universe.faults.count,
                excludedFaultCount: excluded.count,
                detectedFaultCount: detectedCount,
                untestableFaultCount: untestableCount,
                abortedFaultCount: abortedCount,
                coverage: coverage,
                assumptions: [
                    "one deterministic pattern is generated per modeled fault",
                    "coverage denominator is active declared faults after exclusions",
                    "process-specific results require an injected model, validated model result and independent trust evidence",
                    faultSource == .gateLevel
                        ? "fault universe was extracted from driven nets in the canonical gate design"
                        : "fault universe was supplied by the request"
                ],
                evidenceProvenance: evidenceProvenance,
                outcomes: outcomes
            )
            let patternSet = DFTTestPatternSet(
                format: configuration.patternFormat.rawValue,
                seed: seed,
                faultUniverseDigest: universeDigest,
                patterns: patterns
            )
            let evidenceData = try DFTArtifactJSONEncoder().encode(evidence)
            var artifactContents = [
                DFTArtifactContent(
                    artifactID: "dft-fault-universe",
                    fileName: "fault-universe.json",
                    kind: .input,
                    format: .json,
                    data: try DFTArtifactJSONEncoder().encode(universe)
                ),
                DFTArtifactContent(
                    artifactID: "dft-coverage-evidence",
                    fileName: "coverage-evidence.json",
                    kind: .report,
                    format: .json,
                    data: evidenceData
                )
            ]
            if !patterns.isEmpty {
                let patternsData = try DeterministicTestPatternCodec().encode(
                    patternSet,
                    format: configuration.patternFormat
                )
                artifactContents.append(
                    DFTArtifactContent(
                        artifactID: "dft-patterns",
                        fileName: "patterns.\(configuration.patternFormat.rawValue.lowercased())",
                        kind: .testPattern,
                        format: fileFormat(for: configuration.patternFormat),
                        data: patternsData
                    )
                )
            }
            if let scanPatternExecutionPlan {
                artifactContents.append(
                    DFTArtifactContent(
                        artifactID: "dft-scan-pattern-execution-plan",
                        fileName: "scan-pattern-execution-plan.json",
                        kind: .testPattern,
                        format: .json,
                        data: try DFTArtifactJSONEncoder().encode(
                            scanPatternExecutionPlan
                        )
                    )
                )
            }
            let artifacts = try await artifactStore.storeBatch(
                artifactContents,
                runID: request.runID
            )

            let isBlocked = abortedCount > configuration.abortLimit || untestableCount > 0
            if isBlocked {
                diagnostics.append(DFTDiagnostic(
                    severity: .error,
                    code: "DFT_ATPG_BLOCKED",
                    message: "ATPG produced partial evidence but cannot claim coverage because unsupported or untestable faults remain.",
                    suggestedActions: ["qualify_missing_fault_semantics", "increase_pattern_budget", "review_fault_exclusions"]
                ))
            } else if abortedCount > 0 {
                diagnostics.append(DFTDiagnostic(
                    severity: .warning,
                    code: "DFT_ATPG_ABORTS_WITHIN_POLICY",
                    message: "ATPG completed with \(abortedCount) aborted fault(s) within the declared abort limit."
                ))
            }
            diagnostics.insert(
                DFTDiagnostic(
                    severity: .info,
                    code: "DFT_ATPG_COMPLETED",
                    message: faultSource == .gateLevel
                        ? "Exhaustive gate-level ATPG generated \(patterns.count) pattern(s) for \(activeFaults.count) extracted fault(s)."
                        : "Generated \(patterns.count) deterministic pattern(s) for \(activeFaults.count) active fault(s)."
                ),
                at: 0
            )

            return try DFTExecutionSupport.result(
                request: request,
                engineID: engineID,
                implementationID: implementationID,
                status: isBlocked ? .blocked : .completed,
                diagnostics: diagnostics,
                artifacts: artifacts,
                payload: DFTPayload(
                    transformedDesign: nil,
                    faultCoverage: coverage,
                    patterns: patternSet,
                    scanPatternExecutionPlan: scanPatternExecutionPlan,
                    coverageEvidence: evidence,
                    evidenceProvenance: evidenceProvenance,
                    assumptions: evidence.assumptions
                ),
                startedAt: startedAt,
                seed: seed
            )
        } catch is CancellationError {
            return try DFTExecutionSupport.result(
                request: request,
                engineID: engineID,
                implementationID: implementationID,
                status: .cancelled,
                diagnostics: [
                    DFTDiagnostic(
                        severity: .warning,
                        code: "DFT_EXECUTION_CANCELLED",
                        message: "ATPG was cancelled before completion."
                    )
                ],
                payload: DFTPayload(
                    transformedDesign: nil,
                    faultCoverage: nil,
                    evidenceProvenance: evidenceProvenance
                ),
                startedAt: startedAt
            )
        }
    }

    public var capabilityReport: DFTCapabilityReport {
        DFTCapabilityReport(
            engineID: "dft.atpg",
            implementationID: implementationID,
            implementationVersion: DFTExecutionSupport.implementationVersion,
            capabilities: [
                "stuck_at_faults": .available,
                "transition_faults": .available,
                "gate_level_fault_extraction": .available,
                "gate_level_combinational_atpg": .available,
                "sequential_atpg": .available,
                "sequential_control_semantics": .available,
                "sequential_transition_faults": .available,
                "process_specific_faults": processFaultModel != nil
                    && processFaultPatternVerifier != nil
                    && processFaultModel?.modelID
                        != processFaultPatternVerifier?.verifierID
                    ? .available
                    : .blocked,
                "coverage_evidence": .available,
                "stil_export": .blocked,
                "wgl_export": .blocked
            ],
            limitations: [
                "Gate-level ATPG currently supports exhaustive binary simulation for a qualified combinational primitive subset.",
                "Bounded sequential ATPG supports explicit DFF/SDFF SI/SE, reset/set polarity/timing/edge semantics, level-sensitive latches and bounded transition faults; unknown primitives and process-qualified timing remain blocked.",
                "Process-specific fault families require an injected model with validated results; family declarations alone do not provide semantics, and independent ToolQualification evidence remains required."
            ],
            evidenceProvenance: evidenceProvenance
        )
    }

    private func supports(
        fault: DFTFault,
        configuration: DFTATPGConfiguration
    ) -> Bool {
        switch fault.family {
        case .stuckAt:
            return fault.stuckAtValue != nil
        case .transition:
            return false
        case .processSpecific:
            return false
        }
    }

    private func validate(
        cellLibrary: DFTCellLibraryManifest,
        reference: DFTCellLibraryReference,
        pdk: PDKReference
    ) throws {
        try DFTCellLibraryManifestCodec.validate(cellLibrary)
        guard cellLibrary.processID == pdk.processID else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "processID",
                expected: pdk.processID,
                actual: cellLibrary.processID
            )
        }
        guard cellLibrary.version == pdk.version else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "version",
                expected: pdk.version,
                actual: cellLibrary.version
            )
        }
        guard cellLibrary.pdkDigest == pdk.digest else {
            throw DFTCellLibraryError.referenceMismatch(
                field: "pdkDigest",
                expected: pdk.digest,
                actual: cellLibrary.pdkDigest
            )
        }
        guard reference.processID == pdk.processID,
              reference.version == pdk.version else {
            throw DFTCellLibraryError.invalidManifest(
                "cell library reference does not identify the request PDK"
            )
        }
    }

    private func searchGateLevel(
        snapshot: LogicDesignSnapshot,
        faults: [DFTFault],
        configuration: DFTATPGConfiguration,
        sequentialSimulator: any GateLevelSequentialSimulating
    ) throws -> GateLevelATPGSearchResult {
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelATPGError.gateDesignMissing
        }
        let inputPorts = module.ports
            .filter { $0.direction == .input }
            .sorted { $0.name < $1.name }
        let inputLimit = configuration.maximumExhaustiveInputCount ?? 16
        guard inputPorts.count <= inputLimit else {
            throw GateLevelATPGError.inputWidthExceedsLimit(
                count: inputPorts.count,
                limit: inputLimit
            )
        }
        guard configuration.patternLength >= inputPorts.count else {
            throw GateLevelATPGError.patternLengthInsufficient(
                required: inputPorts.count,
                actual: configuration.patternLength
            )
        }
        let hasSequentialCells = module.cells.contains { cell in
            let normalized = cell.type
                .uppercased()
                .replacingOccurrences(of: "_", with: "")
                .replacingOccurrences(of: "-", with: "")
            return normalized.hasPrefix("DFF")
                || normalized.hasPrefix("SDFF")
                || normalized.hasPrefix("SCAN")
                || normalized.hasPrefix("LATCH")
        }
        if hasSequentialCells {
            guard let cycleLimit = configuration.maximumSequentialCycleCount else {
                throw GateLevelATPGError.sequentialSemanticsUnavailable
            }
            guard cycleLimit > 0 else {
                throw GateLevelATPGError.sequentialCycleLimitInvalid
            }
            return try searchSequentialGateLevel(
                snapshot: snapshot,
                module: module,
                faults: faults,
                configuration: configuration,
                cycleLimit: cycleLimit,
                simulator: sequentialSimulator
            )
        }
        let candidateCount = 1 << inputPorts.count
        var outcomes: [DFTFaultOutcome] = []
        var patterns: [DFTTestPattern] = []
        var diagnostics: [DFTDiagnostic] = [
            DFTDiagnostic(
                severity: .info,
                code: "DFT_GATE_LEVEL_FAULT_EXTRACTION_COMPLETED",
                message: "Extracted \(faults.count) stuck-at fault(s) from driven nets in \(gate.topModuleName)."
            )
        ]
        var abortedCount = 0
        var untestableCount = 0

        for fault in faults {
            try Task.checkCancellation()
            if patterns.count >= configuration.maximumPatternCount {
                abortedCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .aborted,
                    reason: "pattern budget exhausted before a detecting pattern was allocated"
                ))
                continue
            }

            var detectingAssignment: Int?
            for assignment in 0..<candidateCount {
                try Task.checkCancellation()
                var inputValues: [String: Bool] = [:]
                for (index, port) in inputPorts.enumerated() {
                    inputValues[port.name] = (assignment & (1 << index)) != 0
                }
                do {
                    let good = try simulator.simulate(
                        snapshot: snapshot,
                        inputs: inputValues,
                        fault: nil
                    )
                    let faulty = try simulator.simulate(
                        snapshot: snapshot,
                        inputs: inputValues,
                        fault: fault
                    )
                    if good.observedValues != faulty.observedValues {
                        detectingAssignment = assignment
                        break
                    }
                } catch let error as GateLevelSimulationError {
                    if case .sequentialControlConflict = error {
                        continue
                    }
                    throw GateLevelATPGError.simulationFailed(
                        faultID: fault.id,
                        message: error.localizedDescription
                    )
                }
            }

            guard let detectingAssignment else {
                untestableCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .untestable,
                    reason: "no exhaustive primary-input assignment changed an observable primary output"
                ))
                diagnostics.append(DFTDiagnostic(
                    severity: .warning,
                    code: "DFT_GATE_LEVEL_FAULT_UNTESTABLE",
                    message: "No detecting pattern was found for gate-level fault \(fault.id).",
                    entity: fault.id,
                    suggestedActions: ["review_fault_observability", "add_scan_observation_points"]
                ))
                continue
            }

            let patternID = "pattern-\(patterns.count + 1)"
            patterns.append(DFTTestPattern(
                id: patternID,
                bits: patternBits(for: detectingAssignment, inputCount: inputPorts.count, length: configuration.patternLength),
                faultIDs: [fault.id]
            ))
            outcomes.append(DFTFaultOutcome(
                faultID: fault.id,
                status: .detected,
                patternID: patternID,
                reason: "detected by exhaustive binary gate-level simulation"
            ))
        }

        diagnostics.append(DFTDiagnostic(
            severity: .info,
            code: "DFT_GATE_LEVEL_ATPG_COMPLETED",
            message: "Evaluated up to \(candidateCount) primary-input assignment(s) per extracted fault."
        ))
        return GateLevelATPGSearchResult(
            outcomes: outcomes,
            patterns: patterns,
            diagnostics: diagnostics,
            abortedCount: abortedCount,
            untestableCount: untestableCount
        )
    }

    private func searchSequentialGateLevel(
        snapshot: LogicDesignSnapshot,
        module: GateModule,
        faults: [DFTFault],
        configuration: DFTATPGConfiguration,
        cycleLimit: Int,
        simulator: any GateLevelSequentialSimulating
    ) throws -> GateLevelATPGSearchResult {
        let inputPorts = module.ports
            .filter { $0.direction == .input }
            .sorted { $0.name < $1.name }
        let totalInputCount = inputPorts.count * cycleLimit
        let inputLimit = configuration.maximumExhaustiveInputCount ?? 16
        guard totalInputCount <= inputLimit else {
            throw GateLevelATPGError.inputWidthExceedsLimit(
                count: totalInputCount,
                limit: inputLimit
            )
        }
        guard configuration.patternLength >= totalInputCount else {
            throw GateLevelATPGError.patternLengthInsufficient(
                required: totalInputCount,
                actual: configuration.patternLength
            )
        }
        let candidateCount = 1 << totalInputCount
        var outcomes: [DFTFaultOutcome] = []
        var patterns: [DFTTestPattern] = []
        var diagnostics: [DFTDiagnostic] = [
            DFTDiagnostic(
                severity: .info,
                code: "DFT_GATE_LEVEL_SEQUENTIAL_SEMANTICS_ENABLED",
                message: "Evaluating bounded DFF and scan-cell state transitions over \(cycleLimit) capture cycle(s)."
            )
        ]
        var abortedCount = 0
        var untestableCount = 0

        for fault in faults {
            try Task.checkCancellation()
            if patterns.count >= configuration.maximumPatternCount {
                abortedCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .aborted,
                    reason: "pattern budget exhausted before a detecting sequential pattern was allocated"
                ))
                continue
            }
            var detectingAssignment: Int?
            for assignment in 0..<candidateCount {
                try Task.checkCancellation()
                var cycles: [[String: Bool]] = []
                for cycle in 0..<cycleLimit {
                    var inputs: [String: Bool] = [:]
                    for (portIndex, port) in inputPorts.enumerated() {
                        let bitIndex = cycle * inputPorts.count + portIndex
                        inputs[port.name] = (assignment & (1 << bitIndex)) != 0
                    }
                    cycles.append(inputs)
                }
                do {
                    let good = try simulator.simulate(
                        snapshot: snapshot,
                        inputCycles: cycles,
                        initialState: [:],
                        fault: nil,
                        sequentialContracts: configuration.sequentialCellContracts
                    )
                    let faulty = try simulator.simulate(
                        snapshot: snapshot,
                        inputCycles: cycles,
                        initialState: [:],
                        fault: fault,
                        sequentialContracts: configuration.sequentialCellContracts
                    )
                    if good.observedValues != faulty.observedValues {
                        detectingAssignment = assignment
                        break
                    }
                } catch let error as GateLevelSimulationError {
                    if case .sequentialControlConflict = error {
                        continue
                    }
                    throw GateLevelATPGError.simulationFailed(
                        faultID: fault.id,
                        message: error.localizedDescription
                    )
                }
            }
            guard let detectingAssignment else {
                untestableCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .untestable,
                    reason: "no bounded sequential input sequence changed an observable primary output"
                ))
                continue
            }
            let patternID = "pattern-\(patterns.count + 1)"
            patterns.append(DFTTestPattern(
                id: patternID,
                bits: sequentialPatternBits(
                    for: detectingAssignment,
                    inputCount: totalInputCount,
                    length: configuration.patternLength
                ),
                faultIDs: [fault.id]
            ))
            outcomes.append(DFTFaultOutcome(
                faultID: fault.id,
                status: .detected,
                patternID: patternID,
                reason: "detected by bounded sequential DFF simulation"
            ))
        }

        diagnostics.append(DFTDiagnostic(
            severity: .info,
            code: "DFT_GATE_LEVEL_SEQUENTIAL_ATPG_COMPLETED",
            message: "Evaluated up to \(candidateCount) sequential input sequence(s) per extracted fault."
        ))
        return GateLevelATPGSearchResult(
            outcomes: outcomes,
            patterns: patterns,
            diagnostics: diagnostics,
            abortedCount: abortedCount,
            untestableCount: untestableCount
        )
    }

    private func searchTransitionFault(
        snapshot: LogicDesignSnapshot,
        fault: DFTFault,
        configuration: DFTATPGConfiguration
    ) throws -> String? {
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw GateLevelATPGError.gateDesignMissing
        }
        let inputPorts = module.ports
            .filter { $0.direction == .input }
            .sorted { $0.name < $1.name }
        let totalInputCount = inputPorts.count * 2
        let inputLimit = configuration.maximumExhaustiveInputCount ?? 16
        guard totalInputCount <= inputLimit else {
            throw GateLevelATPGError.inputWidthExceedsLimit(
                count: totalInputCount,
                limit: inputLimit
            )
        }
        guard configuration.patternLength >= totalInputCount else {
            throw GateLevelATPGError.patternLengthInsufficient(
                required: totalInputCount,
                actual: configuration.patternLength
            )
        }
        let candidateCount = 1 << totalInputCount
        for assignment in 0..<candidateCount {
            try Task.checkCancellation()
            var launch: [String: Bool] = [:]
            var capture: [String: Bool] = [:]
            for (index, port) in inputPorts.enumerated() {
                launch[port.name] = (assignment & (1 << index)) != 0
                capture[port.name] = (assignment & (1 << (inputPorts.count + index))) != 0
            }
            let transition: GateLevelTransitionSimulationResult
            do {
                transition = try transitionSimulator.simulate(
                    snapshot: snapshot,
                    launchInputs: launch,
                    captureInputs: capture,
                    fault: fault,
                    sequentialContracts: configuration.sequentialCellContracts
                )
            } catch let error as GateLevelSimulationError {
                if case .sequentialControlConflict = error {
                    continue
                }
                throw error
            }
            let goodCapture = transition.goodCaptureObservedValues ?? transition.launchObservedValues
            if goodCapture != transition.captureObservedValues {
                return patternBits(
                    for: assignment,
                    inputCount: totalInputCount,
                    length: configuration.patternLength
                )
            }
        }
        return nil
    }

    private func sequentialPatternBits(for assignment: Int, inputCount: Int, length: Int) -> String {
        var bits = Array(repeating: "0", count: length)
        for index in 0..<inputCount {
            bits[index] = (assignment & (1 << index)) == 0 ? "0" : "1"
        }
        return bits.joined()
    }

    private func fileFormat(for format: DFTTestPatternFormat) -> ArtifactFormat {
        switch format {
        case .json:
            return .json
        case .stil:
            return .stil
        case .wgl:
            return .wgl
        }
    }

    private func patternBits(for assignment: Int, inputCount: Int, length: Int) -> String {
        var bits = Array(repeating: "0", count: length)
        for index in 0..<inputCount {
            bits[index] = (assignment & (1 << index)) == 0 ? "0" : "1"
        }
        return bits.joined()
    }

    private var evidenceProvenance: DFTEvidenceProvenance {
        DFTEvidenceProvenance(
            status: .smokeObserved,
            notes: ["deterministic declared-fault model; no external ATPG oracle correlation"]
        )
    }

    private func blocked(
        request: DFTRequest,
        engineID: String,
        startedAt: Date,
        code: String,
        message: String,
        entity: String? = nil,
        actions: [String] = []
    ) throws -> DFTResult {
        try DFTExecutionSupport.result(
            request: request,
            engineID: engineID,
            implementationID: implementationID,
            status: .blocked,
            diagnostics: [
                DFTDiagnostic(
                    severity: .error,
                    code: code,
                    message: message,
                    entity: entity,
                    suggestedActions: actions
                )
            ],
            payload: DFTPayload(
                transformedDesign: nil,
                faultCoverage: nil,
                evidenceProvenance: evidenceProvenance
            ),
            startedAt: startedAt
        )
    }
}

private struct GateLevelATPGSearchResult {
    var outcomes: [DFTFaultOutcome]
    var patterns: [DFTTestPattern]
    var diagnostics: [DFTDiagnostic]
    var abortedCount: Int
    var untestableCount: Int
}
