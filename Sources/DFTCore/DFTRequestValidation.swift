import CircuiteFoundation
import Foundation

public extension DFTRequest {
    func validationIssues(for operation: DFTOperation) -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []

        if schemaVersion != Self.currentSchemaVersion {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCHEMA_VERSION_UNSUPPORTED",
                message: "Request schema version \(schemaVersion) is not supported.",
                suggestedActions: ["upgrade_request_schema"]
            ))
        }
        if runID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_RUN_ID_EMPTY",
                message: "A non-empty run ID is required.",
                entity: "runID",
                suggestedActions: ["provide_stable_run_id"]
            ))
        } else if !isSafeComponent(runID) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_RUN_ID_INVALID",
                message: "Run IDs must be a single safe path component.",
                entity: "runID",
                suggestedActions: ["provide_a_path_safe_run_id"]
            ))
        }
        if self.operation != operation {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_OPERATION_MISMATCH",
                message: "The request declares \(self.operation.rawValue) but the executor is \(operation.rawValue).",
                entity: "operation",
                suggestedActions: ["use_matching_executor"]
            ))
        }
        if design.topDesignName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_TOP_DESIGN_EMPTY",
                message: "A top design name is required.",
                entity: "design.topDesignName",
                suggestedActions: ["declare_top_design"]
            ))
        }
        if design.designDigest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_DESIGN_DIGEST_MISSING",
                message: "The input design must carry a content digest.",
                entity: "design.designDigest",
                suggestedActions: ["recompute_design_digest"]
            ))
        } else if !isSHA256(design.designDigest) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_DESIGN_DIGEST_INVALID",
                message: "The input design digest must be a SHA-256 value.",
                entity: "design.designDigest",
                suggestedActions: ["recompute_design_digest"]
            ))
        }
        issues.append(contentsOf: validateLocator(
            design.artifact.locator,
            entity: "design.artifact"
        ))
        if pdk.processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || pdk.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_PDK_PROVENANCE_INCOMPLETE",
                message: "PDK process ID, version and digest are required.",
                entity: "pdk",
                suggestedActions: ["provide_process_scoped_pdk_reference"]
            ))
        }
        if !isSHA256(pdk.digest) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_PDK_DIGEST_INVALID",
                message: "The PDK digest must be a SHA-256 value.",
                entity: "pdk.digest",
                suggestedActions: ["verify_pdk_manifest_integrity"]
            ))
        }
        do {
            try pdk.validate()
        } catch {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_PDK_IDENTITY_MISMATCH",
                message: error.localizedDescription,
                entity: "pdk",
                suggestedActions: ["repair_pdk_reference_identity"]
            ))
        }
        issues.append(contentsOf: validateArtifact(
            pdk.manifest,
            entity: "pdk.manifest"
        ))
        if constraints.modeIDs.isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_TIMING_MODE_MISSING",
                message: "At least one timing mode is required for DFT execution.",
                entity: "constraints.modeIDs",
                suggestedActions: ["declare_test_timing_mode"]
            ))
        }
        if Set(constraints.modeIDs).count != constraints.modeIDs.count
            || constraints.modeIDs.contains(where: {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_TIMING_MODE_INVALID",
                message: "Timing mode IDs must be non-empty and unique.",
                entity: "constraints.modeIDs",
                suggestedActions: ["declare_unique_timing_modes"]
            ))
        }
        for mode in constraints.modes {
            issues.append(contentsOf: validateArtifact(
                mode.artifact,
                entity: "constraints.modes[\(mode.modeID)].artifact"
            ))
        }
        if inputs.isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_INPUT_ARTIFACTS_EMPTY",
                message: "At least one immutable input artifact reference is required.",
                entity: "inputs",
                suggestedActions: ["attach_design_and_test_artifacts"]
            ))
        }
        for input in inputs {
            issues.append(contentsOf: validateArtifact(input, entity: "inputs"))
        }
        let inputIDs = inputs.compactMap(\.artifactID)
        if Set(inputIDs).count != inputIDs.count {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_INPUT_ARTIFACT_IDS_DUPLICATE",
                message: "Input artifact IDs must be unique.",
                entity: "inputs",
                suggestedActions: ["assign_unique_artifact_ids"]
            ))
        }
        let inputPaths = inputs.map(\.path)
        if Set(inputPaths).count != inputPaths.count {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_INPUT_ARTIFACT_PATHS_DUPLICATE",
                message: "Input artifact paths must be unique.",
                entity: "inputs",
                suggestedActions: ["remove_duplicate_input_artifacts"]
            ))
        }
        if let cellLibrary {
            issues.append(contentsOf: validateArtifact(
                cellLibrary.artifact,
                entity: "cellLibrary.artifact"
            ))
            if let timingLibraryArtifact = cellLibrary.timingLibraryArtifact {
                issues.append(contentsOf: validateArtifact(
                    timingLibraryArtifact,
                    entity: "cellLibrary.timingLibraryArtifact"
                ))
                if timingLibraryArtifact.format != .liberty
                    && timingLibraryArtifact.format != .json {
                    issues.append(DFTRequestValidationIssue(
                        code: "DFT_TIMING_LIBRARY_FORMAT_UNSUPPORTED",
                        message: "Cell timing must be supplied as Liberty or canonical TimingLibrary JSON.",
                        entity: "cellLibrary.timingLibraryArtifact",
                        suggestedActions: ["attach_liberty_timing_library"]
                    ))
                }
            }
            if cellLibrary.processID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || cellLibrary.version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_CELL_LIBRARY_PROVENANCE_INCOMPLETE",
                    message: "Cell-library process ID and version are required.",
                    entity: "cellLibrary",
                    suggestedActions: ["provide_process_scoped_cell_library_reference"]
                ))
            }
            if !isSHA256(cellLibrary.manifestDigest) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_CELL_LIBRARY_DIGEST_INVALID",
                    message: "The cell-library manifest digest must be a SHA-256 value.",
                    entity: "cellLibrary.manifestDigest",
                    suggestedActions: ["verify_cell_library_manifest_integrity"]
                ))
            }
        }
        issues.append(contentsOf: validateScanArchitectureIfPresent())

        switch operation {
        case .scanInsertion:
            if cellLibrary == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_CELL_LIBRARY_MISSING",
                    message: "Scan insertion requires a process-scoped cell library binding manifest.",
                    entity: "cellLibrary",
                    suggestedActions: ["attach_cell_library_binding_manifest", "qualify_scan_cell_mapping"]
                ))
            }
            if scanArchitecture == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_ARCHITECTURE_MISSING",
                    message: "Scan insertion requires a declared scan architecture.",
                    entity: "scanArchitecture",
                    suggestedActions: ["declare_scan_domains_and_chains"]
                ))
            }
            if insertionPolicy == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_INSERTION_POLICY_MISSING",
                    message: "Scan insertion requires an explicit insertion policy.",
                    entity: "insertionPolicy",
                    suggestedActions: ["declare_scan_cell_and_test_mode_policy"]
                ))
            } else if insertionPolicy?.scanCellName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == true {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_CELL_NAME_EMPTY",
                    message: "Scan insertion requires a scan cell name.",
                    entity: "insertionPolicy.scanCellName",
                    suggestedActions: ["declare_scan_cell_name"]
                ))
            } else if insertionPolicy?.preserveFunctionalPorts == false {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_PORT_REMOVAL_UNSUPPORTED",
                    message: "The native scan transformer preserves functional ports and cannot honor a port-removal policy.",
                    entity: "insertionPolicy.preserveFunctionalPorts",
                    suggestedActions: ["preserve_functional_ports", "select_a_qualified_external_backend"]
                ))
            } else if insertionPolicy?.allowUnknownCells == true {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_UNKNOWN_SCAN_CELLS_UNSUPPORTED",
                    message: "Unknown sequential cells cannot be accepted without an explicit process-scoped cell binding.",
                    entity: "insertionPolicy.allowUnknownCells",
                    suggestedActions: ["provide_complete_scan_cell_bindings", "disable_unknown_cell_acceptance"]
                ))
            }
            if cellLibrary?.timingLibraryArtifact == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_TIMING_LIBRARY_MISSING",
                    message: "Scan insertion requires timing evidence for every replacement cell.",
                    entity: "cellLibrary.timingLibraryArtifact",
                    suggestedActions: ["attach_liberty_timing_library"]
                ))
            }
        case .atpg:
            if cellLibrary != nil && cellLibrary?.timingLibraryArtifact == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_TIMING_LIBRARY_MISSING",
                    message: "ATPG requires timing evidence when process-scoped sequential semantics are used.",
                    entity: "cellLibrary.timingLibraryArtifact",
                    suggestedActions: ["attach_liberty_timing_library"]
                ))
            }
            if scanArchitecture == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_ARCHITECTURE_MISSING",
                    message: "ATPG requires a declared scan architecture.",
                    entity: "scanArchitecture",
                    suggestedActions: ["run_scan_insertion_first"]
                ))
            }
            if let universe = faultUniverse {
                issues.append(contentsOf: universe.validationIssues())
            } else if atpgConfiguration?.faultSource != .gateLevel {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_FAULT_UNIVERSE_MISSING",
                    message: "ATPG cannot report coverage without a declared fault universe.",
                    entity: "faultUniverse",
                    suggestedActions: ["declare_fault_universe"]
                ))
            }
            if atpgConfiguration == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_ATPG_CONFIGURATION_MISSING",
                    message: "ATPG requires an explicit pattern and abort policy.",
                    entity: "atpgConfiguration",
                    suggestedActions: ["declare_atpg_limits"]
                ))
            } else if let configuration = atpgConfiguration {
                issues.append(contentsOf: validateATPGConfiguration(configuration))
            }
        case .bist:
            if bistConfiguration == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_BIST_CONFIGURATION_MISSING",
                    message: "BIST requires an explicit controller and target configuration.",
                    entity: "bistConfiguration",
                    suggestedActions: ["declare_bist_controller_and_targets"]
                ))
            } else if bistConfiguration?.kind == .logic,
                      bistConfiguration?.targetBindings == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_BIST_TARGET_BINDINGS_MISSING",
                    message: "Logic BIST requires explicit target input/output pin bindings for canonical gate transformation.",
                    entity: "bistConfiguration.targetBindings",
                    suggestedActions: ["declare_bist_target_pin_bindings", "use_a_declared_structure_only_in_an_external_backend"]
                ))
            } else if let configuration = bistConfiguration,
                      configuration.kind == .logic {
                issues.append(contentsOf: validateLogicBISTConfiguration(configuration))
            } else if bistConfiguration?.kind == .memory,
                      bistConfiguration?.memoryBindings == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_BIST_MEMORY_BINDINGS_MISSING",
                    message: "Memory BIST requires explicit macro port bindings.",
                    entity: "bistConfiguration.memoryBindings",
                    suggestedActions: ["declare_memory_macro_bindings"]
                ))
            } else if let configuration = bistConfiguration,
                      configuration.kind == .memory {
                issues.append(contentsOf: validateMemoryBISTConfiguration(configuration))
            }
        }

        return issues
    }

    private func validateLogicBISTConfiguration(
        _ configuration: DFTBISTConfiguration
    ) -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []
        guard let mapping = configuration.logicCellMapping else {
            return [DFTRequestValidationIssue(
                code: "DFT_BIST_CELL_MAPPING_MISSING",
                message: "Native logic BIST requires a process-bound mapping for every generated helper-cell role.",
                entity: "bistConfiguration.logicCellMapping",
                suggestedActions: ["attach_logic_bist_cell_mapping", "select_a_qualified_external_backend"]
            )]
        }
        issues.append(contentsOf: validateArtifact(
            mapping.artifact,
            entity: "bistConfiguration.logicCellMapping.artifact"
        ))
        guard mapping.processID == pdk.processID,
              mapping.pdkDigest.caseInsensitiveCompare(pdk.digest) == .orderedSame else {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_CELL_MAPPING_PDK_MISMATCH",
                message: "Logic BIST cell mapping must identify the exact request PDK.",
                entity: "bistConfiguration.logicCellMapping",
                suggestedActions: ["select_a_pdk_bound_bist_mapping"]
            ))
            return issues
        }
        let cellTypes = [
            mapping.controllerCellType,
            mapping.inputMuxCellType,
            mapping.responseCaptureCellType,
            mapping.responseCompactorCellType,
            mapping.signatureRegisterCellType,
        ]
        if cellTypes.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) || mapping.controllerCellType != configuration.controllerCellName {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_CELL_MAPPING_INVALID",
                message: "Logic BIST helper-cell types must be non-empty and the controller mapping must match the requested controller.",
                entity: "bistConfiguration.logicCellMapping",
                suggestedActions: ["repair_logic_bist_cell_mapping"]
            ))
        }
        let targetInstances = Set(configuration.targetInstances)
        let bindingInstances = Set(configuration.targetBindings?.map(\.instanceName) ?? [])
        if targetInstances.isEmpty || targetInstances != bindingInstances {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_TARGET_SET_MISMATCH",
                message: "Logic BIST target instances must exactly match the bound target instances.",
                entity: "bistConfiguration.targetInstances",
                suggestedActions: ["align_bist_targets_and_bindings"]
            ))
        }
        if mapping.prpgPolynomialTaps.isEmpty
            || mapping.misrPolynomialTaps.isEmpty
            || Set(mapping.prpgPolynomialTaps).count != mapping.prpgPolynomialTaps.count
            || Set(mapping.misrPolynomialTaps).count != mapping.misrPolynomialTaps.count
            || mapping.prpgPolynomialTaps.contains(where: { $0 <= 0 })
            || mapping.misrPolynomialTaps.contains(where: { $0 <= 0 })
            || mapping.expectedSignature.isEmpty
            || !mapping.expectedSignature.allSatisfy({ $0 == "0" || $0 == "1" }) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_ALGORITHM_CONTRACT_INVALID",
                message: "Logic BIST requires unique positive PRPG/MISR taps and a non-empty binary expected signature.",
                entity: "bistConfiguration.logicCellMapping",
                suggestedActions: ["repair_bist_polynomials_and_signature"]
            ))
        }
        return issues
    }

    private func validateMemoryBISTConfiguration(
        _ configuration: DFTBISTConfiguration
    ) -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []
        guard let bindings = configuration.memoryBindings,
              !bindings.isEmpty,
              bindings.allSatisfy(\.isStructurallyComplete) else {
            return [DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_BINDINGS_INVALID",
                message: "Native memory BIST requires complete macro port bindings.",
                entity: "bistConfiguration.memoryBindings",
                suggestedActions: ["declare_complete_memory_macro_bindings"]
            )]
        }
        guard let mapping = configuration.memoryCellMapping else {
            return [DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_CELL_MAPPING_MISSING",
                message: "Native memory BIST requires a process-bound helper-cell and macro mapping.",
                entity: "bistConfiguration.memoryCellMapping",
                suggestedActions: ["attach_memory_bist_cell_mapping"]
            )]
        }
        issues.append(contentsOf: validateArtifact(
            mapping.artifact,
            entity: "bistConfiguration.memoryCellMapping.artifact"
        ))
        if mapping.processID != pdk.processID
            || mapping.pdkDigest.caseInsensitiveCompare(pdk.digest) != .orderedSame {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_CELL_MAPPING_PDK_MISMATCH",
                message: "Memory-BIST mapping must identify the exact request PDK.",
                entity: "bistConfiguration.memoryCellMapping",
                suggestedActions: ["select_a_pdk_bound_memory_bist_mapping"]
            ))
        }
        let cellTypes = [
            mapping.controllerCellType,
            mapping.inputMuxCellType,
            mapping.responseCompactorCellType,
            mapping.signatureRegisterCellType,
        ]
        if cellTypes.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) || mapping.controllerCellType != configuration.controllerCellName {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_CELL_MAPPING_INVALID",
                message: "Memory-BIST helper-cell types must be non-empty and the controller mapping must match the request.",
                entity: "bistConfiguration.memoryCellMapping",
                suggestedActions: ["repair_memory_bist_cell_mapping"]
            ))
        }
        let targetNames = configuration.targetInstances
        let bindingNames = bindings.map(\.instanceName)
        if targetNames.isEmpty
            || Set(targetNames).count != targetNames.count
            || Set(bindingNames).count != bindingNames.count
            || Set(targetNames) != Set(bindingNames) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_TARGET_SET_MISMATCH",
                message: "Memory-BIST targets must exactly match unique macro bindings.",
                entity: "bistConfiguration.targetInstances",
                suggestedActions: ["align_memory_bist_targets_and_bindings"]
            ))
        }
        let macroTypes = Set(bindings.map(\.macroType))
        let algorithmIDs = Set(bindings.map(\.algorithmID))
        if !macroTypes.isSubset(of: Set(mapping.supportedMacroTypes))
            || !algorithmIDs.isSubset(of: Set(mapping.supportedAlgorithmIDs)) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_BIST_MEMORY_CAPABILITY_UNQUALIFIED",
                message: "Memory-BIST mapping does not qualify every bound macro type and algorithm.",
                entity: "bistConfiguration.memoryCellMapping",
                suggestedActions: ["qualify_memory_macro_and_algorithm_mapping"]
            ))
        }
        return issues
    }

    private func validateArtifact(
        _ artifact: ArtifactReference,
        entity: String
    ) -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []
        do {
            _ = try ArtifactID(rawValue: artifact.artifactID)
        } catch {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ARTIFACT_ID_INVALID",
                message: "Artifact IDs must be valid CircuiteFoundation tokens.",
                entity: "\(entity).artifactID",
                suggestedActions: ["assign_a_stable_artifact_id"]
            ))
        }
        if !isSafePath(artifact.path) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ARTIFACT_PATH_INVALID",
                message: "Artifact paths must be project-relative and remain inside the project root.",
                entity: "\(entity).path",
                suggestedActions: ["provide_a_safe_project_relative_path"]
            ))
        }
        let digest = artifact.digest.hexadecimalValue
        if artifact.digest.algorithm != .sha256 || !isSHA256(digest) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ARTIFACT_DIGEST_INVALID",
                message: "Artifact digests must be 64 hexadecimal SHA-256 characters.",
                entity: "\(entity).sha256",
                suggestedActions: ["recompute_artifact_digest"]
            ))
        }
        return issues
    }

    private func validateLocator(
        _ locator: ArtifactLocator,
        entity: String
    ) -> [DFTRequestValidationIssue] {
        guard !locator.path.isEmpty else {
            return [DFTRequestValidationIssue(
                code: "DFT_ARTIFACT_PATH_INVALID",
                message: "Artifact locators require a non-empty path.",
                entity: "\(entity).path",
                suggestedActions: ["provide_a_safe_project_relative_path"]
            )]
        }
        return []
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.allSatisfy(\.isHexDigit)
    }

    private func isSafePath(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("/"),
              !value.hasPrefix("~"),
              !value.contains("\\"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return false
        }
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    private func isSafeComponent(_ value: String) -> Bool {
        !value.isEmpty
            && value != "."
            && value != ".."
            && !value.contains("/")
            && !value.contains("\\")
            && !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }

    private func validateATPGConfiguration(
        _ configuration: DFTATPGConfiguration
    ) -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []
        if configuration.maximumPatternCount <= 0
            || configuration.patternLength <= 0
            || configuration.abortLimit < 0 {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ATPG_LIMITS_INVALID",
                message: "ATPG pattern count and length must be positive and abort limit cannot be negative.",
                entity: "atpgConfiguration",
                suggestedActions: ["provide_positive_atpg_limits"]
            ))
        }
        if let limit = configuration.maximumExhaustiveInputCount, limit <= 0 {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ATPG_INPUT_LIMIT_INVALID",
                message: "The exhaustive input limit must be positive when provided.",
                entity: "atpgConfiguration.maximumExhaustiveInputCount",
                suggestedActions: ["provide_a_positive_input_limit"]
            ))
        }
        if let limit = configuration.maximumSequentialCycleCount, limit <= 0 {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_ATPG_CYCLE_LIMIT_INVALID",
                message: "The sequential cycle limit must be positive when provided.",
                entity: "atpgConfiguration.maximumSequentialCycleCount",
                suggestedActions: ["provide_a_positive_cycle_limit"]
            ))
        }
        if configuration.supportedProcessFamilies.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) || Set(configuration.supportedProcessFamilies).count
            != configuration.supportedProcessFamilies.count {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_PROCESS_FAMILIES_INVALID",
                message: "Supported process fault families must be non-empty and unique.",
                entity: "atpgConfiguration.supportedProcessFamilies",
                suggestedActions: ["declare_unique_process_fault_families"]
            ))
        }
        switch configuration.patternFormat {
        case .json:
            break
        case .stil, .wgl:
            issues.append(DFTRequestValidationIssue(
                code: "DFT_STANDARD_PATTERN_EXPORT_UNQUALIFIED",
                message: "The native backend does not yet provide a qualified cycle-accurate STIL or WGL exporter.",
                entity: "atpgConfiguration.patternFormat",
                suggestedActions: ["use_json_pattern_ir", "select_a_qualified_standard_pattern_backend"]
            ))
        }
        let contractTypes = configuration.sequentialCellContracts.flatMap(\.cellTypes)
        if contractTypes.contains(where: {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }) || Set(contractTypes).count != contractTypes.count {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SEQUENTIAL_CONTRACTS_INVALID",
                message: "Sequential cell contract type names must be non-empty and unique.",
                entity: "atpgConfiguration.sequentialCellContracts",
                suggestedActions: ["declare_unambiguous_sequential_contracts"]
            ))
        }
        return issues
    }

    private func validateScanArchitectureIfPresent() -> [DFTRequestValidationIssue] {
        guard let architecture = scanArchitecture else { return [] }
        var issues: [DFTRequestValidationIssue] = []
        if architecture.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_ARCHITECTURE_NAME_EMPTY",
                message: "Scan architecture name is required.",
                entity: "scanArchitecture.name"
            ))
        }
        let clockIDs = architecture.clocks.map(\.id)
        if Set(clockIDs).count != clockIDs.count || clockIDs.contains(where: { $0.isEmpty }) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_CLOCK_IDS_INVALID",
                message: "Scan clock IDs must be non-empty and unique.",
                entity: "scanArchitecture.clocks"
            ))
        }
        let resetIDs = architecture.resets.map(\.id)
        if Set(resetIDs).count != resetIDs.count || resetIDs.contains(where: { $0.isEmpty }) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_RESET_IDS_INVALID",
                message: "Scan reset IDs must be non-empty and unique.",
                entity: "scanArchitecture.resets"
            ))
        }
        let domainIDs = architecture.domains.map(\.id)
        if Set(domainIDs).count != domainIDs.count || domainIDs.contains(where: { $0.isEmpty }) {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_DOMAIN_IDS_INVALID",
                message: "Scan domain IDs must be non-empty and unique.",
                entity: "scanArchitecture.domains"
            ))
        }
        let knownClocks = Set(clockIDs)
        let knownResets = Set(resetIDs)
        for domain in architecture.domains {
            if !knownClocks.contains(domain.clockID) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_CLOCK_REFERENCE_MISSING",
                    message: "Scan domain \(domain.id) references unknown clock \(domain.clockID).",
                    entity: "scanArchitecture.domains.\(domain.id).clockID",
                    suggestedActions: ["declare_referenced_scan_clock"]
                ))
            }
            if let resetID = domain.resetID, !knownResets.contains(resetID) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_RESET_REFERENCE_MISSING",
                    message: "Scan domain \(domain.id) references unknown reset \(resetID).",
                    entity: "scanArchitecture.domains.\(domain.id).resetID",
                    suggestedActions: ["declare_referenced_scan_reset"]
                ))
            }
            if domain.chainCount <= 0 || domain.estimatedElementCount <= 0 {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_DOMAIN_DIMENSIONS_INVALID",
                    message: "Scan domain \(domain.id) must have positive chain and element counts.",
                    entity: "scanArchitecture.domains.\(domain.id)",
                    suggestedActions: ["provide_positive_chain_dimensions"]
                ))
            }
            if let maximum = domain.maximumChainLength, maximum <= 0 {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_MAX_CHAIN_LENGTH_INVALID",
                    message: "Maximum chain length for \(domain.id) must be positive.",
                    entity: "scanArchitecture.domains.\(domain.id).maximumChainLength"
                ))
            }
        }
        for clock in architecture.clocks {
            if clock.signalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || clock.periodNanoseconds <= 0
                || !(clock.dutyCycle > 0 && clock.dutyCycle < 1) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_SCAN_CLOCK_PARAMETERS_INVALID",
                    message: "Scan clock \(clock.id) must have a signal, positive period and duty cycle in (0, 1).",
                    entity: "scanArchitecture.clocks.\(clock.id)",
                    suggestedActions: ["declare_valid_scan_clock_parameters"]
                ))
            }
        }
        for reset in architecture.resets where reset.signalName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_RESET_SIGNAL_EMPTY",
                message: "Scan reset \(reset.id) must declare a signal name.",
                entity: "scanArchitecture.resets.\(reset.id).signalName",
                suggestedActions: ["declare_scan_reset_signal"]
            ))
        }
        if architecture.scanEnableSignal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || architecture.testModeSignal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_SCAN_CONTROL_SIGNAL_MISSING",
                message: "Scan enable and test-mode control signals are required.",
                entity: "scanArchitecture",
                suggestedActions: ["declare_scan_control_signals"]
            ))
        }
        if let compression = architecture.compression, compression.enabled {
            let chainCount = architecture.domains.reduce(0) { $0 + $1.chainCount }
            if let ratio = compression.ratio, ratio < 1 {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_COMPRESSION_RATIO_INVALID",
                    message: "Compression ratio must be at least one.",
                    entity: "scanArchitecture.compression.ratio"
                ))
            } else if compression.ratio == nil {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_COMPRESSION_RATIO_MISSING",
                    message: "Enabled compression requires an explicit ratio.",
                    entity: "scanArchitecture.compression.ratio",
                    suggestedActions: ["declare_compression_ratio"]
                ))
            }
            let lists = [
                compression.scanInputSignals,
                compression.scanOutputSignals,
            ]
            if lists.contains(where: {
                $0.isEmpty
                    || $0.contains(where: {
                        $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    })
                    || Set($0).count != $0.count
            }) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_COMPRESSION_CHANNELS_INVALID",
                    message: "Compression signal and pin lists must be non-empty, unique and contain no empty names.",
                    entity: "scanArchitecture.compression",
                    suggestedActions: ["declare_unambiguous_compression_channels"]
                ))
            }
            let externalSignals =
                compression.scanInputSignals + compression.scanOutputSignals
            let internalSignals = architecture.domains.flatMap { domain in
                (0..<domain.chainCount).flatMap { index in
                    [
                        "\(architecture.scanInPrefix)_\(domain.id)_\(index)",
                        "\(architecture.scanOutPrefix)_\(domain.id)_\(index)",
                    ]
                }
            }
            let reservedSignals =
                [architecture.scanEnableSignal, architecture.testModeSignal]
                + internalSignals
            if Set(externalSignals).count != externalSignals.count
                || !Set(externalSignals).isDisjoint(with: reservedSignals) {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_COMPRESSION_CHANNEL_CONFLICT",
                    message: "External compression channels must be mutually distinct and must not reuse control or internal-chain signal names.",
                    entity: "scanArchitecture.compression",
                    suggestedActions: ["rename_compression_channels"]
                ))
            }
            if !compression.scanInputSignals.isEmpty,
               let ratio = compression.ratio {
                let actualRatio = Double(chainCount) / Double(compression.scanInputSignals.count)
                if abs(actualRatio - ratio) > 0.000_001 {
                    issues.append(DFTRequestValidationIssue(
                        code: "DFT_COMPRESSION_RATIO_MISMATCH",
                        message: "Declared compression ratio \(ratio) does not match \(chainCount) internal chains over \(compression.scanInputSignals.count) external scan inputs.",
                        entity: "scanArchitecture.compression.ratio",
                        suggestedActions: ["align_compression_ratio_with_channels"]
                    ))
                }
            }
        }
        return issues
    }
}

public extension DFTFaultUniverse {
    func validationIssues() -> [DFTRequestValidationIssue] {
        var issues: [DFTRequestValidationIssue] = []
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_FAULT_UNIVERSE_NAME_EMPTY",
                message: "Fault universe name is required.",
                entity: "faultUniverse.name"
            ))
        }
        if revision.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_FAULT_UNIVERSE_REVISION_EMPTY",
                message: "Fault universe revision is required.",
                entity: "faultUniverse.revision"
            ))
        }
        if declaredBy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_FAULT_UNIVERSE_DECLARATION_MISSING",
                message: "Fault universe provenance is required.",
                entity: "faultUniverse.declaredBy"
            ))
        }
        let faultIDs = faults.map(\.id)
        if faults.isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_FAULT_UNIVERSE_EMPTY",
                message: "Coverage cannot be computed from an empty fault universe.",
                entity: "faultUniverse.faults",
                suggestedActions: ["declare_fault_instances"]
            ))
        }
        if faultIDs.contains(where: { $0.isEmpty }) || Set(faultIDs).count != faultIDs.count {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_FAULT_IDS_INVALID",
                message: "Fault IDs must be non-empty and unique.",
                entity: "faultUniverse.faults"
            ))
        }
        let known = Set(faultIDs)
        let unknownExclusions = excludedFaultIDs.filter { !known.contains($0) }
        if !unknownExclusions.isEmpty {
            issues.append(DFTRequestValidationIssue(
                code: "DFT_EXCLUDED_FAULT_UNKNOWN",
                message: "Excluded faults must be members of the declared fault universe.",
                entity: "faultUniverse.excludedFaultIDs",
                suggestedActions: ["remove_unknown_exclusions"]
            ))
        }
        for fault in faults where fault.family == .processSpecific {
            if fault.processFamily?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                issues.append(DFTRequestValidationIssue(
                    code: "DFT_PROCESS_FAULT_FAMILY_MISSING",
                    message: "Process-specific faults require a declared process family.",
                    entity: "faultUniverse.faults.\(fault.id).processFamily",
                    suggestedActions: ["declare_process_specific_fault_family"]
                ))
            }
        }
        return issues
    }
}
