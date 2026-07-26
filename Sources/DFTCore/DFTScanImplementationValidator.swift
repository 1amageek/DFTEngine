import Foundation

public struct DFTScanImplementationValidator:
    DFTScanImplementationValidating
{
    public init() {}

    public func validationIssues(
        in implementation: DFTScanImplementation
    ) -> [DFTScanImplementationValidationIssue] {
        var issues: [DFTScanImplementationValidationIssue] = []
        if implementation.schemaVersion
            != DFTScanImplementation.currentSchemaVersion
        {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_SCHEMA_UNSUPPORTED",
                "The scan implementation schema version is unsupported."
            ))
        }
        if implementation.architectureName.isEmpty
            || !isSHA256(implementation.sourceDesignDigest)
            || !isSHA256(implementation.transformedDesignDigest)
        {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_IDENTITY_INVALID",
                "Architecture and design digest identities must be complete."
            ))
        }
        if !isIdentifier(implementation.scanEnableSignal)
            || implementation.scanEnableNetID.isEmpty
            || !isIdentifier(implementation.testModeSignal)
            || implementation.testModeNetID.isEmpty
            || implementation.scanEnableSignal
                == implementation.testModeSignal
        {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_CONTROL_INVALID",
                "Scan-enable and test-mode signal and net identities must be distinct and complete."
            ))
        }
        if implementation.chains.isEmpty {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_CHAINS_EMPTY",
                "At least one realized scan chain is required."
            ))
            return issues
        }
        let chainIDs = implementation.chains.map(\.chainID)
        let scanInputs = implementation.chains.map(\.scanInSignal)
        let scanOutputs = implementation.chains.map(\.scanOutSignal)
        if Set(chainIDs).count != chainIDs.count
            || Set(scanInputs).count != scanInputs.count
            || Set(scanOutputs).count != scanOutputs.count
            || !Set(scanInputs).isDisjoint(with: Set(scanOutputs))
        {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_CHAIN_IDENTITY_INVALID",
                "Chain, scan-input, and scan-output identities must be unique."
            ))
        }
        var cellIDs: Set<String> = []
        for chain in implementation.chains {
            validate(
                chain: chain,
                implementation: implementation,
                cellIDs: &cellIDs,
                issues: &issues
            )
        }
        return issues
    }

    private func validate(
        chain: DFTRealizedScanChain,
        implementation: DFTScanImplementation,
        cellIDs: inout Set<String>,
        issues: inout [DFTScanImplementationValidationIssue]
    ) {
        guard !chain.chainID.isEmpty,
              !chain.domainID.isEmpty,
              isIdentifier(chain.scanInSignal),
              !chain.scanInNetID.isEmpty,
              isIdentifier(chain.scanOutSignal),
              !chain.scanOutNetID.isEmpty,
              !chain.elements.isEmpty else {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_CHAIN_INCOMPLETE",
                "Every realized chain requires complete identities and elements."
            ))
            return
        }
        guard chain.elements.first?.scanInNetID == chain.scanInNetID,
              chain.elements.last?.outputNetID == chain.scanOutNetID else {
            issues.append(issue(
                "DFT_SCAN_IMPLEMENTATION_CHAIN_BOUNDARY_INVALID",
                "Realized chain boundaries do not match their elements."
            ))
            return
        }
        for (index, element) in chain.elements.enumerated() {
            guard element.position == index,
                  cellIDs.insert(element.cellID).inserted,
                  !element.cellID.isEmpty,
                  !element.instanceName.isEmpty,
                  !element.cellType.isEmpty,
                  !element.dataPinName.isEmpty,
                  !element.dataNetID.isEmpty,
                  !element.outputPinName.isEmpty,
                  !element.outputNetID.isEmpty,
                  !element.clockPinName.isEmpty,
                  !element.clockNetID.isEmpty,
                  !element.scanInPinName.isEmpty,
                  !element.scanInNetID.isEmpty,
                  !element.scanEnablePinName.isEmpty,
                  element.scanEnableNetID
                    == implementation.scanEnableNetID,
                  validTestMode(
                      element,
                      expectedNetID: implementation.testModeNetID
                  ) else {
                issues.append(issue(
                    "DFT_SCAN_IMPLEMENTATION_ELEMENT_INVALID",
                    "Realized scan elements require contiguous positions and complete unique bindings."
                ))
                return
            }
            if index > 0,
               chain.elements[index - 1].outputNetID
                != element.scanInNetID {
                issues.append(issue(
                    "DFT_SCAN_IMPLEMENTATION_CONNECTIVITY_INVALID",
                    "Adjacent realized scan elements are disconnected."
                ))
                return
            }
        }
    }

    private func validTestMode(
        _ element: DFTScanElementBinding,
        expectedNetID: String
    ) -> Bool {
        if let pinName = element.testModePinName {
            return !pinName.isEmpty
                && element.testModeNetID == expectedNetID
        }
        return element.testModeNetID == nil
    }

    private func issue(
        _ code: String,
        _ message: String
    ) -> DFTScanImplementationValidationIssue {
        DFTScanImplementationValidationIssue(code: code, message: message)
    }

    private func isIdentifier(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z_][A-Za-z0-9_$]*$"#,
            options: .regularExpression
        ) != nil
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9a-fA-F]{64}$"#,
            options: .regularExpression
        ) != nil
    }
}
