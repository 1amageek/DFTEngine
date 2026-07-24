import Foundation
import DFTCore
import LogicIR
import PDKCore

public struct DeterministicScanInsertionEngine: ScanInserting {
    public let artifactStore: any DFTArtifactStoring
    public let designLoader: (any DFTDesignLoading)?
    public let cellLibraryLoader: (any DFTCellLibraryLoading)?
    public let timingLibraryLoader: (any DFTTimingLibraryLoading)?
    public let constraintLoader: any DFTConstraintLoading
    public let implementationID: String

    public init(
        artifactStore: any DFTArtifactStoring = InMemoryDFTArtifactStore(),
        designLoader: (any DFTDesignLoading)? = nil,
        cellLibraryLoader: (any DFTCellLibraryLoading)? = nil,
        timingLibraryLoader: (any DFTTimingLibraryLoading)? = nil,
        constraintLoader: any DFTConstraintLoading = UnavailableDFTConstraintLoader(),
        implementationID: String = "native-deterministic-scan"
    ) {
        self.artifactStore = artifactStore
        self.designLoader = designLoader
        self.cellLibraryLoader = cellLibraryLoader
        self.timingLibraryLoader = timingLibraryLoader
        self.constraintLoader = constraintLoader
        self.implementationID = implementationID
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        let startedAt = Date()
        let engineID = "dft.scan-insertion"
        do {
            try Task.checkCancellation()
            let issues = request.validationIssues(for: .scanInsertion)
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
                        assumptions: ["scan insertion was not attempted because request prerequisites are incomplete"]
                    ),
                    startedAt: startedAt
                )
            }
            guard let architecture = request.scanArchitecture,
                  let policy = request.insertionPolicy else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_SCAN_PREREQUISITE_MISSING",
                    message: "Scan architecture and insertion policy are required."
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
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_CONSTRAINT_VALIDATION_FAILED",
                    message: error.localizedDescription,
                    entity: request.constraints.artifacts.first?.path ?? "constraints",
                    actions: ["provide_constraint_loader", "repair_test_mode_constraints"]
                )
            }
            let plan: DFTScanPlan
            do {
                plan = try DeterministicScanPlanner().plan(architecture)
            } catch let error as DFTScanPlanningError {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_SCAN_PLAN_INVALID",
                    message: error.localizedDescription,
                    entity: architecture.name,
                    actions: ["repair_scan_architecture"]
                )
            }
            try Task.checkCancellation()

            guard let cellLibraryReference = request.cellLibrary else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_CELL_LIBRARY_MISSING",
                    message: "Scan insertion requires a process-scoped cell library binding manifest.",
                    entity: "cellLibrary",
                    actions: ["attach_cell_library_binding_manifest", "qualify_scan_cell_mapping"]
                )
            }
            guard let cellLibraryLoader else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_CELL_LIBRARY_LOADER_MISSING",
                    message: "Scan insertion cannot verify the process-scoped cell library manifest.",
                    entity: cellLibraryReference.artifact.locator.path,
                    actions: ["provide_cell_library_loader", "persist_cell_library_manifest"]
                )
            }

            let cellLibrary: DFTCellLibraryManifest
            do {
                cellLibrary = try cellLibraryLoader.load(cellLibraryReference)
                try validate(cellLibrary: cellLibrary, reference: cellLibraryReference, pdk: request.pdk)
                guard let timingReference = cellLibraryReference.timingLibraryArtifact,
                      let timingLibraryLoader else {
                    throw DFTCellLibraryTimingError.timingCellMissing(
                        bindingID: "<all>",
                        cellName: "<timing-library>"
                    )
                }
                let timingLibrary = try timingLibraryLoader.load(timingReference)
                _ = try DFTCellLibraryTimingValidator().validate(
                    manifest: cellLibrary,
                    timingLibrary: timingLibrary
                )
            } catch {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_CELL_LIBRARY_LOAD_FAILED",
                    message: error.localizedDescription,
                    entity: cellLibraryReference.artifact.locator.path,
                    actions: ["verify_cell_library_digest", "align_cell_library_with_pdk", "attach_qualification_evidence"]
                )
            }

            guard let designLoader else {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_DESIGN_LOADER_MISSING",
                    message: "Scan insertion requires a canonical LogicDesignSnapshot loader; declared architecture metadata alone is insufficient.",
                    entity: "design.artifact",
                    actions: ["provide_gate_level_design_loader", "run_logic_elaboration_or_gate_parse"]
                )
            }

            let sourceSnapshot: LogicDesignSnapshot
            do {
                sourceSnapshot = try designLoader.load(request.design)
            } catch {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_DESIGN_LOAD_FAILED",
                    message: error.localizedDescription,
                    entity: request.design.artifact.path,
                    actions: ["verify_design_artifact_digest", "provide_valid_gate_level_snapshot"]
                )
            }

            let transform: DFTGateLevelScanTransformResult
            do {
                transform = try DFTGateLevelScanTransformer().transform(
                    snapshot: sourceSnapshot,
                    architecture: architecture,
                    plan: plan,
                    policy: policy,
                    cellLibrary: cellLibrary
                )
            } catch {
                return try blocked(
                    request: request,
                    engineID: engineID,
                    implementationID: implementationID,
                    startedAt: startedAt,
                    code: "DFT_GATE_LEVEL_TRANSFORM_FAILED",
                    message: error.localizedDescription,
                    entity: request.design.topDesignName,
                    actions: ["repair_gate_level_design", "align_scan_architecture_with_sequential_cells"]
                )
            }

            let transformedArtifact = DFTTransformedDesignArtifact(
                runID: request.runID,
                operation: .scanInsertion,
                sourceDesign: request.design,
                scanPlan: plan,
                assumptions: [
                    "the canonical LogicDesignSnapshot was loaded and digest-verified",
                    "the process-scoped cell library manifest was loaded and PDK-bound",
                    "the gate-level snapshot was transformed and validated before persistence"
                ]
            )
            let transformedData = try LogicDesignSnapshotCodec.encode(transform.snapshot)
            let transformedReference = try await artifactStore.store(
                DFTArtifactContent(
                    artifactID: "dft-transformed-design",
                    fileName: "transformed-design.json",
                    kind: .netlist,
                    format: .json,
                    data: transformedData
                ),
                runID: request.runID
            )
            let transformedDesign = LogicDesignReference(
                artifact: transformedReference,
                topDesignName: request.design.topDesignName,
                designDigest: transform.snapshot.designDigest ?? "",
                provenance: LogicDesignProvenance(
                    sourceDesignDigest: request.design.provenance?.sourceDesignDigest ?? request.design.designDigest,
                    inputDesignDigest: request.design.designDigest,
                    transformationID: "dft-scan-insertion",
                    producerID: "DFTEngine",
                    producerVersion: implementationID,
                    runID: request.runID
                )
            )

            var artifacts = [transformedReference]
            var designDiff: DFTDesignDiff?
            if policy.generateDesignDiff {
                let changes = transform.transformedCellIDs.map { cellID in
                    DFTDesignDiffChange(
                        changeID: "transform-\(cellID)",
                        domain: .circuit,
                        operation: .modify,
                        path: "gate.modules[\(request.design.topDesignName)].cells[\(cellID)]",
                        after: .string("scan cell \(policy.scanCellName) with SI/SE/TM connectivity"),
                        summary: "Transform sequential cell \(cellID) into a scan cell."
                    )
                }
                let generatedChanges = changes + transform.helperCellIDs.map { cellID in
                    DFTDesignDiffChange(
                        changeID: "add-\(cellID)",
                        domain: .circuit,
                        operation: .add,
                        path: "gate.modules[\(request.design.topDesignName)].cells[\(cellID)]",
                        after: .string("DFT scan observability helper"),
                        summary: "Add scan observability helper cell \(cellID)."
                    )
                }
                guard let baseReference = request.inputs.first(where: {
                    $0 == request.design.artifact
                }) else {
                    return try blocked(
                        request: request,
                        engineID: engineID,
                        implementationID: implementationID,
                        startedAt: startedAt,
                        code: "DFT_DESIGN_INPUT_MISSING",
                        message: "The source design artifact is missing from the request input set.",
                        entity: request.design.topDesignName,
                        actions: ["include_source_design_artifact"]
                    )
                }
                let diff = DFTDesignDiff(
                    runID: request.runID,
                    title: "Insert scan architecture \(architecture.name)",
                    actor: "DFTEngine/\(implementationID)",
                    baseSnapshot: baseReference,
                    proposedSnapshot: transformedReference,
                    changes: generatedChanges,
                    createdAt: startedAt
                )
                let diffData = try DFTArtifactJSONEncoder().encode(diff)
                let diffReference = try await artifactStore.store(
                    DFTArtifactContent(
                        artifactID: "dft-design-diff",
                        fileName: "design-diff.json",
                        kind: .designDiff,
                        format: .json,
                        data: diffData
                    ),
                    runID: request.runID
                )
                artifacts.append(diffReference)
                designDiff = diff
            }

            return try DFTExecutionSupport.result(
                request: request,
                engineID: engineID,
                implementationID: implementationID,
                status: .completed,
                diagnostics: [
                    DFTDiagnostic(
                        severity: .info,
                        code: "DFT_SCAN_INSERTION_COMPLETED",
                        message: "Generated \(plan.chains.count) scan chain(s) for \(architecture.name) using \(cellLibrary.bindings.count) cell-library binding contract(s).",
                        entity: architecture.name
                    )
                ],
                artifacts: artifacts,
                payload: DFTPayload(
                    transformedDesign: transformedDesign,
                    faultCoverage: nil,
                    scanPlan: plan,
                    designDiff: designDiff,
                    evidenceProvenance: evidenceProvenance(for: cellLibrary),
                    assumptions: transformedArtifact.assumptions + transform.assumptions
                ),
                startedAt: startedAt
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
                        message: "Scan insertion was cancelled before completion."
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
            engineID: "dft.scan-insertion",
            implementationID: implementationID,
            implementationVersion: DFTExecutionSupport.implementationVersion,
            capabilities: [
                "scan_architecture_planning": .available,
                "gate_level_scan_transformation": .available,
                "canonical_snapshot_digest_verification": .available,
                "process_scoped_cell_library_binding": .available,
                "process_qualified_cell_library": .blocked,
                "immutable_design_artifact": .available,
                "design_diff": .available,
                "physical_scan_routing": .unsupported
            ],
            limitations: [
                "The binding manifest is verified, but process-qualified timing arcs and legal library mapping require M6 evidence.",
                "Top-level scan observability routing and physical legality require downstream physical-design and signoff evidence.",
                "A self-declared evidenceProvenance status is not promoted to process evidenceProvenance by this backend."
            ],
            evidenceProvenance: evidenceProvenance
        )
    }

    private var evidenceProvenance: DFTEvidenceProvenance {
        DFTEvidenceProvenance(
            status: .smokeObserved,
            notes: ["canonical gate transformation; no process oracle correlation"]
        )
    }

    private func evidenceProvenance(for manifest: DFTCellLibraryManifest) -> DFTEvidenceProvenance {
        var result = manifest.evidenceProvenance
        result.processID = result.processID ?? manifest.processID
        result.notes.append("cell-library manifest binding was digest and PDK reference checked")
        return result
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

    private func blocked(
        request: DFTRequest,
        engineID: String,
        implementationID: String,
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
