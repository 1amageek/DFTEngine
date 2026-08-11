public struct DFTCanonicalStateValidator: Sendable {
    public init() {}

    public func validate(
        scanPlan: DFTScanPlan,
        scanImplementation: DFTScanImplementation?,
        atpgConfiguration: DFTATPGConfiguration?,
        bistStructures: [DFTBISTStructure]
    ) -> DFTCanonicalValidationReport {
        var findings: [DFTCanonicalValidationFinding] = []
        validate(scanPlan, findings: &findings)
        if let scanImplementation {
            let issues = DFTScanImplementationValidator().validationIssues(
                in: scanImplementation
            )
            findings.append(contentsOf: issues.map {
                DFTCanonicalValidationFinding(
                    code: $0.code,
                    summary: $0.message
                )
            })
            if scanImplementation.architectureName != scanPlan.architecture.name {
                findings.append(finding(
                    "DFT_CANONICAL_ARCHITECTURE_MISMATCH",
                    "The realized scan implementation does not match the canonical scan plan."
                ))
            }
        }
        if let atpgConfiguration {
            validate(atpgConfiguration, findings: &findings)
            if scanImplementation == nil {
                findings.append(finding(
                    "DFT_CANONICAL_ATPG_SCAN_IMPLEMENTATION_MISSING",
                    "ATPG configuration requires a realized scan implementation."
                ))
            }
        }
        validate(bistStructures, findings: &findings)
        return DFTCanonicalValidationReport(findings: findings)
    }

    private func validate(
        _ plan: DFTScanPlan,
        findings: inout [DFTCanonicalValidationFinding]
    ) {
        let architecture = plan.architecture
        if architecture.name.isEmpty
            || architecture.scanEnableSignal.isEmpty
            || architecture.testModeSignal.isEmpty
            || architecture.scanEnableSignal == architecture.testModeSignal {
            findings.append(finding(
                "DFT_CANONICAL_SCAN_ARCHITECTURE_INVALID",
                "The scan architecture identity and control signals are invalid."
            ))
        }
        validateUnique(architecture.clocks.map(\.id), kind: "clock", findings: &findings)
        validateUnique(architecture.resets.map(\.id), kind: "reset", findings: &findings)
        validateUnique(architecture.domains.map(\.id), kind: "domain", findings: &findings)
        validateUnique(plan.chains.map(\.id), kind: "chain", findings: &findings)
        let clockIDs = Set(architecture.clocks.map(\.id))
        let resetIDs = Set(architecture.resets.map(\.id))
        let domainIDs = Set(architecture.domains.map(\.id))
        for clock in architecture.clocks {
            if clock.id.isEmpty || clock.signalName.isEmpty
                || !clock.periodNanoseconds.isFinite || clock.periodNanoseconds <= 0
                || !clock.dutyCycle.isFinite
                || clock.dutyCycle <= 0 || clock.dutyCycle >= 1 {
                findings.append(finding(
                    "DFT_CANONICAL_SCAN_CLOCK_INVALID",
                    "A scan clock has an invalid identity or waveform.",
                    clock.id
                ))
            }
        }
        for domain in architecture.domains {
            if domain.id.isEmpty || !clockIDs.contains(domain.clockID)
                || domain.resetID.map({ !resetIDs.contains($0) }) == true
                || domain.chainCount <= 0 || domain.estimatedElementCount <= 0
                || domain.maximumChainLength.map({ $0 <= 0 }) == true {
                findings.append(finding(
                    "DFT_CANONICAL_SCAN_DOMAIN_INVALID",
                    "A scan domain has invalid references or capacity.",
                    domain.id
                ))
            }
        }
        var chainElements = 0
        var maximumLength = 0
        for chain in plan.chains {
            if chain.id.isEmpty || !domainIDs.contains(chain.domainID)
                || chain.index < 0 || chain.estimatedElementCount <= 0
                || chain.scanInSignal.isEmpty || chain.scanOutSignal.isEmpty {
                findings.append(finding(
                    "DFT_CANONICAL_SCAN_CHAIN_INVALID",
                    "A planned scan chain has invalid identity, domain, or capacity.",
                    chain.id
                ))
            }
            chainElements += chain.estimatedElementCount
            maximumLength = max(maximumLength, chain.estimatedElementCount)
        }
        if plan.chains.isEmpty
            || chainElements != plan.totalEstimatedElementCount
            || maximumLength != plan.maximumEstimatedChainLength {
            findings.append(finding(
                "DFT_CANONICAL_SCAN_TOTAL_MISMATCH",
                "Scan plan totals do not match the declared chains."
            ))
        }
    }

    private func validate(
        _ configuration: DFTATPGConfiguration,
        findings: inout [DFTCanonicalValidationFinding]
    ) {
        if configuration.maximumPatternCount <= 0
            || configuration.patternLength <= 0
            || configuration.abortLimit < 0
            || configuration.maximumExhaustiveInputCount.map({ $0 <= 0 }) == true
            || configuration.maximumSequentialCycleCount.map({ $0 <= 0 }) == true {
            findings.append(finding(
                "DFT_CANONICAL_ATPG_CONFIGURATION_INVALID",
                "ATPG limits must be explicit positive bounds with a nonnegative abort limit."
            ))
        }
    }

    private func validate(
        _ structures: [DFTBISTStructure],
        findings: inout [DFTCanonicalValidationFinding]
    ) {
        validateUnique(structures.map(\.name), kind: "bist", findings: &findings)
        for structure in structures {
            if structure.name.isEmpty || structure.controllerCellName.isEmpty
                || structure.targetInstances.isEmpty
                || Set(structure.targetInstances).count != structure.targetInstances.count
                || structure.patternCount <= 0
                || structure.signatureRegisterName.isEmpty
                || structure.testModeSignal.isEmpty {
                findings.append(finding(
                    "DFT_CANONICAL_BIST_STRUCTURE_INVALID",
                    "A BIST structure has incomplete identity, targets, or pattern policy.",
                    structure.name
                ))
            }
            if let bindings = structure.memoryBindings,
               bindings.contains(where: { !$0.isStructurallyComplete }) {
                findings.append(finding(
                    "DFT_CANONICAL_MEMORY_BIST_BINDING_INVALID",
                    "A memory BIST binding is structurally incomplete.",
                    structure.name
                ))
            }
        }
    }

    private func validateUnique(
        _ values: [String],
        kind: String,
        findings: inout [DFTCanonicalValidationFinding]
    ) {
        var seen = Set<String>()
        for value in values where !seen.insert(value).inserted {
            findings.append(finding(
                "DFT_CANONICAL_\(kind.uppercased())_DUPLICATE",
                "Canonical \(kind) identities must be unique.",
                value
            ))
        }
    }

    private func finding(
        _ code: String,
        _ summary: String,
        _ entity: String? = nil
    ) -> DFTCanonicalValidationFinding {
        DFTCanonicalValidationFinding(code: code, summary: summary, entity: entity)
    }
}
