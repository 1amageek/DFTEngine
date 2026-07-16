import Foundation
import DFTCore
import LogicIR

public struct DeterministicBISTEngine: BISTExecuting {
    public let artifactStore: any DFTArtifactStoring
    public let designLoader: (any DFTDesignLoading)?
    public let implementationID: String

    public init(
        artifactStore: any DFTArtifactStoring = InMemoryDFTArtifactStore(),
        designLoader: (any DFTDesignLoading)? = nil,
        implementationID: String = "native-deterministic-bist"
    ) {
        self.artifactStore = artifactStore
        self.designLoader = designLoader
        self.implementationID = implementationID
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        let startedAt = Date()
        let engineID = "dft.bist"
        do {
            try Task.checkCancellation()
            let issues = request.validationIssues(for: .bist)
            guard issues.isEmpty else {
                return DFTExecutionSupport.result(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    status: .blocked,
                    diagnostics: DFTExecutionSupport.diagnostics(for: issues),
                    payload: DFTPayload(
                        transformedDesign: nil,
                        faultCoverage: nil,
                        evidenceProvenance: evidenceProvenance,
                        assumptions: ["BIST insertion was not attempted because request prerequisites are incomplete"]
                    ),
                    startedAt: startedAt
                )
            }
            guard let configuration = request.bistConfiguration else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_PREREQUISITE_MISSING",
                    message: "BIST configuration is required."
                )
            }
            let testModeSignal = configuration.testModeSignal
                ?? request.testIntent?.testModeSignal
                ?? request.scanArchitecture?.testModeSignal
            guard let testModeSignal, !testModeSignal.isEmpty else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_TEST_MODE_MISSING",
                    message: "BIST insertion requires an explicit test-mode signal.",
                    entity: "bistConfiguration.testModeSignal",
                    actions: ["declare_bist_test_mode_signal"]
                )
            }
            guard !configuration.name.isEmpty,
                  !configuration.controllerCellName.isEmpty,
                  !configuration.signatureRegisterName.isEmpty,
                  !configuration.targetInstances.isEmpty,
                  configuration.patternCount > 0 else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_CONFIGURATION_INVALID",
                    message: "BIST name, controller, signature register, targets and pattern count are required.",
                    entity: "bistConfiguration",
                    actions: ["provide_complete_bist_configuration"]
                )
            }
            guard configuration.kind == .logic else {
                guard configuration.memoryBindings?.isEmpty == false,
                      configuration.memoryBindings?.allSatisfy(\.isStructurallyComplete) == true else {
                    return blocked(
                        request: request,
                        engineID: engineID,
                        startedAt: startedAt,
                        code: "DFT_BIST_MEMORY_BINDINGS_MISSING",
                        message: "Memory BIST requires complete macro port bindings before an external qualified adapter can run.",
                        entity: "bistConfiguration.memoryBindings",
                        actions: ["declare_memory_macro_bindings", "inject_a_qualified_memory_bist_adapter"]
                    )
                }
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_MEMORY_MACRO_UNSUPPORTED",
                    message: "Native BIST does not transform memory macros; the declared macro binding must be executed by a qualified external adapter.",
                    entity: "bistConfiguration.kind",
                    actions: ["inject_memory_bist_adapter", "use_a_qualified_external_backend"]
                )
            }
            guard configuration.targetBindings?.isEmpty == false else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_TARGET_BINDINGS_MISSING",
                    message: "Canonical logic BIST requires target input/output pin bindings.",
                    entity: "bistConfiguration.targetBindings",
                    actions: ["declare_bist_target_pin_bindings"]
                )
            }
            guard let designLoader else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_DESIGN_LOADER_MISSING",
                    message: "Canonical BIST requires a digest-verified LogicDesignSnapshot loader.",
                    entity: "design",
                    actions: ["inject_design_loader", "provide_gate_level_design_artifact"]
                )
            }
            let clockSignal = configuration.clockSignal
                ?? request.scanArchitecture?.clocks.first?.signalName
            guard let clockSignal, !clockSignal.isEmpty else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_CLOCK_MISSING",
                    message: "Canonical logic BIST requires an explicit clock signal.",
                    entity: "bistConfiguration.clockSignal",
                    actions: ["declare_bist_clock_signal"]
                )
            }
            let sourceSnapshot: LogicDesignSnapshot
            do {
                sourceSnapshot = try designLoader.load(request.design)
            } catch {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_DESIGN_LOAD_FAILED",
                    message: "Could not load the canonical design for BIST: \(error.localizedDescription)",
                    entity: request.design.artifact.path,
                    actions: ["verify_design_artifact_integrity", "repair_gate_level_snapshot"]
                )
            }
            let transform: DFTGateLevelBISTTransformResult
            do {
                transform = try DFTGateLevelBISTTransformer().transform(
                    snapshot: sourceSnapshot,
                    configuration: configuration,
                    testModeSignal: testModeSignal,
                    clockSignal: clockSignal
                )
            } catch {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_BIST_GATE_LEVEL_TRANSFORM_FAILED",
                    message: error.localizedDescription,
                    entity: request.design.topDesignName,
                    actions: ["repair_bist_target_bindings", "repair_gate_connectivity", "qualify_bist_helper_cells"]
                )
            }
            let seed = configuration.randomSeed
                ?? DFTDeterministicHasher().seed(for: "\(request.design.designDigest):\(configuration.name)")
            let structure = DFTBISTStructure(
                name: configuration.name,
                kind: configuration.kind,
                controllerCellName: configuration.controllerCellName,
                targetInstances: configuration.targetInstances.sorted(),
                patternCount: configuration.patternCount,
                signatureRegisterName: configuration.signatureRegisterName,
                seed: seed,
                testModeSignal: testModeSignal
            )
            let transformedArtifact = DFTTransformedDesignArtifact(
                runID: request.runID,
                operation: .bist,
                sourceDesign: request.design,
                bistStructure: structure,
                assumptions: [
                    "the canonical LogicDesignSnapshot was loaded and digest-verified",
                    "target input pins are isolated through explicit test-mode mux structures",
                    "target output pins are captured and compacted into a signature path",
                    "controller, mux and compactor helper cells require process evidenceProvenance before physical signoff"
                ]
            )
            let transformedData = try LogicDesignSnapshotCodec.encode(transform.snapshot)
            let transformedReference = try await artifactStore.store(
                DFTArtifactContent(
                    artifactID: "dft-bist-transformed-design",
                    fileName: "bist-transformed-design.json",
                    kind: .netlist,
                    format: .json,
                    data: transformedData
                ),
                runID: request.runID
            )
            let structureData = try DFTArtifactJSONEncoder().encode(structure)
            let structureReference = try await artifactStore.store(
                DFTArtifactContent(
                    artifactID: "dft-bist-structure",
                    fileName: "bist-structure.json",
                    kind: .netlist,
                    format: .json,
                    data: structureData
                ),
                runID: request.runID
            )
            let transformedDesign = LogicDesignReference(
                artifact: transformedReference.locator,
                topDesignName: request.design.topDesignName,
                designDigest: transform.snapshot.designDigest ?? "",
                provenance: LogicDesignProvenance(
                    sourceDesignDigest: request.design.provenance?.sourceDesignDigest ?? request.design.designDigest,
                    inputDesignDigest: request.design.designDigest,
                    transformationID: "dft-bist-insertion",
                    producerID: "DFTEngine",
                    producerVersion: implementationID,
                    runID: request.runID
                )
            )
            guard let baseReference = request.inputs.first(where: {
                $0.locator == request.design.artifact
            }) else {
                return blocked(
                    request: request,
                    engineID: engineID,
                    startedAt: startedAt,
                    code: "DFT_DESIGN_INPUT_MISSING",
                    message: "The source design artifact is missing from the request input set.",
                    entity: request.design.topDesignName,
                    actions: ["include_source_design_artifact"]
                )
            }
            let diff = DFTDesignDiff(
                runID: request.runID,
                title: "Insert \(configuration.kind.rawValue) BIST \(configuration.name)",
                actor: "DFTEngine/\(implementationID)",
                baseSnapshot: baseReference,
                proposedSnapshot: transformedReference,
                changes: transform.generatedCellIDs.map { cellID in
                    DFTDesignDiffChange(
                        changeID: "add-\(cellID)",
                        domain: .circuit,
                        operation: .add,
                        path: "gate.modules[\(request.design.topDesignName)].cells[\(cellID)]",
                        after: .string("canonical BIST helper cell"),
                        summary: "Add BIST helper cell \(cellID)."
                    )
                } + transform.transformedTargetInstances.map { instanceName in
                    DFTDesignDiffChange(
                        changeID: "transform-\(instanceName)",
                        domain: .circuit,
                        operation: .modify,
                        path: "gate.modules[\(request.design.topDesignName)].cells[\(instanceName)]",
                        after: .string("test-mode isolated BIST target binding"),
                        summary: "Add test-mode BIST isolation around target \(instanceName)."
                    )
                }
            )
            let diffData = try DFTArtifactJSONEncoder().encode(diff)
            let diffReference = try await artifactStore.store(
                DFTArtifactContent(
                    artifactID: "dft-bist-design-diff",
                    fileName: "bist-design-diff.json",
                    kind: .designDiff,
                    format: .json,
                    data: diffData
                ),
                runID: request.runID
            )

            return DFTExecutionSupport.result(
                request: request,
                engineID: engineID,
                implementationID: implementationID,
                status: .completed,
                diagnostics: [
                    DFTDiagnostic(
                        severity: .info,
                        code: "DFT_BIST_INSERTION_COMPLETED",
                        message: "Transformed canonical gate design for \(configuration.kind.rawValue) BIST \(configuration.name).",
                        entity: configuration.name
                    )
                ],
                artifacts: [transformedReference, structureReference, diffReference],
                payload: DFTPayload(
                    transformedDesign: transformedDesign,
                    faultCoverage: nil,
                    designDiff: diff,
                    bistStructure: structure,
                    evidenceProvenance: evidenceProvenance,
                    assumptions: transformedArtifact.assumptions
                ),
                startedAt: startedAt,
                seed: seed
            )
        } catch is CancellationError {
            return DFTExecutionSupport.result(
                request: request,
                engineID: engineID,
                implementationID: implementationID,
                status: .cancelled,
                diagnostics: [
                    DFTDiagnostic(
                        severity: .warning,
                        code: "DFT_EXECUTION_CANCELLED",
                        message: "BIST insertion was cancelled before completion."
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
            engineID: "dft.bist",
            implementationID: implementationID,
            implementationVersion: DFTExecutionSupport.implementationVersion,
            capabilities: [
                "logic_bist_structure": .available,
                "canonical_gate_bist_transformation": .available,
                "memory_bist_structure": .blocked,
                "immutable_design_artifact": .available,
                "design_diff": .available,
                "memory_macro_legality": .blocked
            ],
            limitations: [
                "The native logic path transforms a bounded canonical gate contract; helper cells require process evidenceProvenance.",
                "Memory BIST remains blocked without a qualified macro adapter.",
                "The generated structure does not claim functional equivalence until a downstream gate approves it."
            ],
            evidenceProvenance: evidenceProvenance
        )
    }

    private var evidenceProvenance: DFTEvidenceProvenance {
        DFTEvidenceProvenance(
            status: .smokeObserved,
            notes: ["deterministic structure generation; no macro oracle correlation"]
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
    ) -> DFTResult {
        DFTExecutionSupport.result(
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
