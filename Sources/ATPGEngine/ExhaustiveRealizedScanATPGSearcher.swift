import DFTCore
import LogicIR

public struct ExhaustiveRealizedScanATPGSearcher: RealizedScanATPGSearching {
    public init() {}

    public func search(
        snapshot: LogicDesignSnapshot,
        faults: [DFTFault],
        configuration: DFTATPGConfiguration,
        architecture: DFTScanArchitecture?,
        implementation: DFTScanImplementation,
        implementationDigest: String,
        sequentialSimulator: any GateLevelSequentialSimulating
    ) throws -> RealizedScanATPGSearchResult {
        guard let architecture else {
            throw GateLevelATPGError.scanExecutionUnsupported(
                "a scan architecture is required"
            )
        }
        guard architecture.compression?.enabled != true else {
            throw GateLevelATPGError.scanExecutionUnsupported(
                "compressed scan requires a qualified compression model"
            )
        }
        guard architecture.clocks.count == 1,
              let clock = architecture.clocks.first,
              Set(architecture.domains.map(\.clockID)) == Set([clock.id]) else {
            throw GateLevelATPGError.scanExecutionUnsupported(
                "the native profile requires one rising-edge scan clock domain"
            )
        }
        let clockPeriodPicoseconds = clock.periodNanoseconds * 1_000
        guard clock.periodNanoseconds.isFinite,
              clockPeriodPicoseconds.isFinite,
              clockPeriodPicoseconds > 1,
              clockPeriodPicoseconds <= Double(Int64.max) else {
            throw GateLevelATPGError.scanExecutionUnsupported(
                "the scan clock period cannot be represented exactly enough in picoseconds"
            )
        }
        guard faults.allSatisfy({
            $0.family == .stuckAt && $0.stuckAtValue != nil
        }) else {
            throw GateLevelATPGError.scanExecutionUnsupported(
                "the native realized-scan profile currently supports stuck-at faults only"
            )
        }
        guard let gate = snapshot.gate,
              let module = gate.modules.first(where: {
                  $0.name == gate.topModuleName
              }) else {
            throw GateLevelATPGError.gateDesignMissing
        }
        try validate(
            implementation,
            architecture: architecture,
            snapshot: snapshot,
            module: module,
            configuration: configuration
        )
        let clockPortName = try realizedClockPortName(
            implementation: implementation,
            module: module
        )
        let excludedSignals = Set(
            [
                clock.signalName,
                clockPortName,
                architecture.scanEnableSignal,
                architecture.testModeSignal,
            ]
                + architecture.resets.map(\.signalName)
                + implementation.chains.map(\.scanInSignal)
        )
        let functionalInputs = module.ports
            .filter {
                $0.direction == .input && !excludedSignals.contains($0.name)
            }
            .sorted { $0.name < $1.name }
        let elements = implementation.chains.flatMap(\.elements)
        let exhaustiveBitCount = elements.count + functionalInputs.count
        let inputLimit = configuration.maximumExhaustiveInputCount ?? 16
        guard exhaustiveBitCount <= inputLimit,
              exhaustiveBitCount < Int.bitWidth - 1 else {
            throw GateLevelATPGError.inputWidthExceedsLimit(
                count: exhaustiveBitCount,
                limit: inputLimit
            )
        }
        let candidateCount = 1 << exhaustiveBitCount
        let inactiveControls = inactiveSequentialControls(
            module: module,
            configuration: configuration
        )
        var outcomes: [DFTFaultOutcome] = []
        var patterns: [DFTTestPattern] = []
        var executions: [DFTScanPatternExecution] = []
        var diagnostics: [DFTDiagnostic] = [
            DFTDiagnostic(
                severity: .info,
                code: "DFT_REALIZED_SCAN_ATPG_ENABLED",
                message: "ATPG is bound to \(implementation.chains.count) retained scan chain(s) and \(elements.count) exact scan element(s)."
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
                    reason: "pattern budget exhausted before a realized-scan pattern was allocated"
                ))
                continue
            }
            let detected = try detectionCandidate(
                for: fault,
                candidateCount: candidateCount,
                exhaustiveBitCount: exhaustiveBitCount,
                elements: elements,
                functionalInputs: functionalInputs,
                inactiveControls: inactiveControls,
                clockPortName: clockPortName,
                architecture: architecture,
                implementation: implementation,
                snapshot: snapshot,
                configuration: configuration,
                simulator: sequentialSimulator
            )
            guard let detected else {
                untestableCount += 1
                outcomes.append(DFTFaultOutcome(
                    faultID: fault.id,
                    status: .untestable,
                    reason: "no exhaustive realized-scan state and functional-input assignment exposed the fault"
                ))
                diagnostics.append(DFTDiagnostic(
                    severity: .warning,
                    code: "DFT_REALIZED_SCAN_FAULT_UNTESTABLE",
                    message: "No realized-scan detecting pattern was found for \(fault.id).",
                    entity: fault.id,
                    suggestedActions: [
                        "review_scan_observability",
                        "add_test_points",
                        "increase_exhaustive_scan_limit",
                    ]
                ))
                continue
            }
            let patternID = "pattern-\(patterns.count + 1)"
            patterns.append(DFTTestPattern(
                id: patternID,
                bits: compactPatternBits(
                    assignment: detected.assignment,
                    exhaustiveBitCount: exhaustiveBitCount,
                    length: configuration.patternLength
                ),
                faultIDs: [fault.id]
            ))
            executions.append(DFTScanPatternExecution(
                id: patternID,
                faultIDs: [fault.id],
                chains: stimuli(
                    implementation: implementation,
                    candidate: detected
                ),
                capture: DFTScanCapture(
                    primaryInputs: detected.captureInputs,
                    expectedPrimaryOutputs:
                        detected.goodResult.observedValues.last ?? [:]
                )
            ))
            outcomes.append(DFTFaultOutcome(
                faultID: fault.id,
                status: .detected,
                patternID: patternID,
                reason: "detected by exact scan-state load, functional capture and state/output comparison"
            ))
        }
        diagnostics.append(DFTDiagnostic(
            severity: .info,
            code: "DFT_REALIZED_SCAN_ATPG_COMPLETED",
            message: "Evaluated up to \(candidateCount) exact scan-state and functional-input assignment(s) per fault."
        ))
        return RealizedScanATPGSearchResult(
            outcomes: outcomes,
            patterns: patterns,
            diagnostics: diagnostics,
            abortedCount: abortedCount,
            untestableCount: untestableCount,
            executionPlan: DFTScanPatternExecutionPlan(
                scanImplementationDigest: implementationDigest,
                transformedDesignDigest: implementation
                    .transformedDesignDigest,
                clockSignal: clockPortName,
                clockPeriodPicoseconds: UInt64(
                    clockPeriodPicoseconds.rounded()
                ),
                scanEnableSignal: architecture.scanEnableSignal,
                testModeSignal: architecture.testModeSignal,
                patterns: executions
            )
        )
    }

    private func detectionCandidate(
        for fault: DFTFault,
        candidateCount: Int,
        exhaustiveBitCount: Int,
        elements: [DFTScanElementBinding],
        functionalInputs: [RTLPort],
        inactiveControls: [String: Bool],
        clockPortName: String,
        architecture: DFTScanArchitecture,
        implementation: DFTScanImplementation,
        snapshot: LogicDesignSnapshot,
        configuration: DFTATPGConfiguration,
        simulator: any GateLevelSequentialSimulating
    ) throws -> RealizedScanDetectionCandidate? {
        guard let module = snapshot.gate?.modules.first(where: {
            $0.name == snapshot.gate?.topModuleName
        }) else {
            throw GateLevelATPGError.gateDesignMissing
        }
        for assignment in 0..<candidateCount {
            try Task.checkCancellation()
            let initialState = Dictionary(
                uniqueKeysWithValues: elements.enumerated().map {
                    index, element in
                    (
                        element.outputNetID,
                        (assignment & (1 << index)) != 0
                    )
                }
            )
            var inputs: [String: Bool] = [:]
            for port in module.ports where port.direction == .input {
                inputs[port.name] = false
            }
            for (index, port) in functionalInputs.enumerated() {
                inputs[port.name] = (
                    assignment & (1 << (elements.count + index))
                ) != 0
            }
            for (name, value) in inactiveControls {
                inputs[name] = value
            }
            inputs[architecture.scanEnableSignal] = false
            inputs[architecture.testModeSignal] = true
            inputs[clockPortName] = true
            for chain in implementation.chains {
                inputs[chain.scanInSignal] = false
            }
            let good = try simulator.simulate(
                snapshot: snapshot,
                inputCycles: [inputs],
                initialState: initialState,
                fault: nil,
                sequentialContracts: configuration.sequentialCellContracts
            )
            let faulty = try simulator.simulate(
                snapshot: snapshot,
                inputCycles: [inputs],
                initialState: initialState,
                fault: fault,
                sequentialContracts: configuration.sequentialCellContracts
            )
            if good.observedValues != faulty.observedValues
                || good.finalState != faulty.finalState {
                return RealizedScanDetectionCandidate(
                    assignment: assignment,
                    initialState: initialState,
                    captureInputs: inputs,
                    goodResult: good
                )
            }
        }
        return nil
    }

    private func stimuli(
        implementation: DFTScanImplementation,
        candidate: RealizedScanDetectionCandidate
    ) -> [DFTScanChainStimulus] {
        implementation.chains.map { chain in
            let outputNetIDs = chain.elements.map(\.outputNetID)
            return DFTScanChainStimulus(
                chainID: chain.chainID,
                scanInSignal: chain.scanInSignal,
                scanOutSignal: chain.scanOutSignal,
                elementOutputNetIDs: outputNetIDs,
                loadBits: binaryString(outputNetIDs.reversed().map {
                    candidate.initialState[$0] == true
                }),
                expectedUnloadBits: binaryString(
                    outputNetIDs.reversed().map {
                        candidate.goodResult.finalState[$0] == true
                    }
                )
            )
        }
    }

    private func realizedClockPortName(
        implementation: DFTScanImplementation,
        module: GateModule
    ) throws -> String {
        let clockNetIDs = Set(
            implementation.chains.flatMap(\.elements).map(\.clockNetID)
        )
        guard clockNetIDs.count == 1,
              let clockNetID = clockNetIDs.first else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "the realized scan clock is not bound to one top-level input"
            )
        }
        let inputPortIDs = Set(
            module.ports.filter { $0.direction == .input }.map(\.id)
        )
        let clockPortIDs = module.portBindings.compactMap {
            $0.netID == clockNetID && inputPortIDs.contains($0.portID)
                ? $0.portID
                : nil
        }
        guard clockPortIDs.count == 1,
              let portName = module.ports.first(where: {
                  $0.id == clockPortIDs[0]
              })?.name else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "the realized scan clock is not bound to one top-level input"
            )
        }
        return portName
    }

    private func validate(
        _ implementation: DFTScanImplementation,
        architecture: DFTScanArchitecture,
        snapshot: LogicDesignSnapshot,
        module: GateModule,
        configuration: DFTATPGConfiguration
    ) throws {
        let snapshotDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        guard implementation.architectureName == architecture.name,
              implementation.transformedDesignDigest == snapshotDigest,
              implementation.scanEnableSignal == architecture.scanEnableSignal,
              implementation.testModeSignal == architecture.testModeSignal else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "architecture or transformed-design identity differs"
            )
        }
        let expectedChainCount = architecture.domains.reduce(0) {
            $0 + $1.chainCount
        }
        guard implementation.chains.count == expectedChainCount,
              !implementation.chains.isEmpty else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "realized chain count differs from the declared architecture"
            )
        }
        let netIDs = Set(module.nets.map(\.id))
        let portsByID = Dictionary(
            uniqueKeysWithValues: module.ports.map { ($0.id, $0) }
        )
        var boundPortsByNetID: [String: [RTLPort]] = [:]
        for binding in module.portBindings {
            guard let port = portsByID[binding.portID] else {
                throw GateLevelATPGError.scanImplementationMismatch(
                    "top-level port bindings reference an unknown port"
                )
            }
            boundPortsByNetID[binding.netID, default: []].append(port)
        }
        guard boundPortsByNetID[implementation.scanEnableNetID]?.contains(
            where: {
                $0.name == implementation.scanEnableSignal
                    && $0.direction == .input
            }
        ) == true,
              boundPortsByNetID[implementation.testModeNetID]?.contains(
                where: {
                    $0.name == implementation.testModeSignal
                        && $0.direction == .input
                }
              ) == true else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "scan-enable or test-mode evidence is detached from its top-level input"
            )
        }
        var cellsByID: [String: GateCell] = [:]
        for cell in module.cells {
            guard cellsByID.updateValue(cell, forKey: cell.id) == nil else {
                throw GateLevelATPGError.scanImplementationMismatch(
                    "the transformed design contains duplicate cell identity \(cell.id)"
                )
            }
        }
        var retainedCellIDs = Set<String>()
        var retainedOutputNetIDs = Set<String>()
        var retainedChainIDs = Set<String>()
        var retainedScanInSignals = Set<String>()
        var retainedScanOutSignals = Set<String>()
        var chainCountsByDomain: [String: Int] = [:]
        for chain in implementation.chains {
            guard retainedChainIDs.insert(chain.chainID).inserted,
                  retainedScanInSignals.insert(chain.scanInSignal).inserted,
                  retainedScanOutSignals.insert(chain.scanOutSignal).inserted,
                  architecture.domains.contains(where: {
                      $0.id == chain.domainID
                  }),
                  boundPortsByNetID[chain.scanInNetID]?.contains(where: {
                      $0.name == chain.scanInSignal && $0.direction == .input
                  }) == true,
                  boundPortsByNetID[chain.scanOutNetID]?.contains(where: {
                      $0.name == chain.scanOutSignal && $0.direction == .output
                  }) == true,
                  !chain.elements.isEmpty,
                  chain.elements.indices.allSatisfy({
                      chain.elements[$0].position == $0
                  }),
                  chain.elements.first?.scanInNetID == chain.scanInNetID,
                  chain.elements.last?.outputNetID == chain.scanOutNetID else {
                throw GateLevelATPGError.scanImplementationMismatch(
                    "chain \(chain.chainID) has invalid order or endpoints"
                )
            }
            chainCountsByDomain[chain.domainID, default: 0] += 1
            for (index, element) in chain.elements.enumerated() {
                guard let cell = cellsByID[element.cellID],
                      cell.instanceName == element.instanceName,
                      cell.type == element.cellType,
                      netIDs.contains(element.dataNetID),
                      netIDs.contains(element.outputNetID),
                      netIDs.contains(element.clockNetID),
                      netIDs.contains(element.scanInNetID),
                      netIDs.contains(element.scanEnableNetID),
                      cell.pins.contains(where: {
                          $0.name == element.outputPinName
                            && $0.netID == element.outputNetID
                      }),
                      cell.pins.contains(where: {
                          $0.name == element.dataPinName
                            && $0.netID == element.dataNetID
                      }),
                      cell.pins.contains(where: {
                          $0.name == element.clockPinName
                            && $0.netID == element.clockNetID
                      }),
                      cell.pins.contains(where: {
                          $0.name == element.scanInPinName
                            && $0.netID == element.scanInNetID
                      }),
                      cell.pins.contains(where: {
                          $0.name == element.scanEnablePinName
                            && $0.netID == element.scanEnableNetID
                      }),
                      retainedCellIDs.insert(element.cellID).inserted,
                      retainedOutputNetIDs.insert(element.outputNetID).inserted,
                      element.scanEnableNetID
                        == implementation.scanEnableNetID else {
                    throw GateLevelATPGError.scanImplementationMismatch(
                        "element \(element.cellID) is detached from the transformed design"
                    )
                }
                switch (element.testModePinName, element.testModeNetID) {
                case let (.some(pinName), .some(netID)):
                    guard netID == implementation.testModeNetID,
                          netIDs.contains(netID),
                          cell.pins.contains(where: {
                              $0.name == pinName && $0.netID == netID
                          }) else {
                        throw GateLevelATPGError.scanImplementationMismatch(
                            "element \(element.cellID) has detached test-mode connectivity"
                        )
                    }
                case (nil, nil):
                    break
                default:
                    throw GateLevelATPGError.scanImplementationMismatch(
                        "element \(element.cellID) has incomplete test-mode connectivity"
                    )
                }
                if index > 0,
                   chain.elements[index - 1].outputNetID
                    != element.scanInNetID {
                    throw GateLevelATPGError.scanImplementationMismatch(
                        "chain \(chain.chainID) has a broken serial edge"
                    )
                }
                if let contract = configuration.sequentialCellContracts.first(
                    where: { $0.matches(cellType: element.cellType) }
                ), contract.elementKind != .edgeTriggered
                    || contract.clockEdge != .rising {
                    throw GateLevelATPGError.scanExecutionUnsupported(
                        "latches and non-rising-edge scan cells require a separate timing profile"
                    )
                }
            }
        }
        guard architecture.domains.allSatisfy({
            chainCountsByDomain[$0.id] == $0.chainCount
        }), retainedCellIDs.count == architecture.domains.reduce(0, {
            $0 + $1.estimatedElementCount
        }) else {
            throw GateLevelATPGError.scanImplementationMismatch(
                "realized chain or element coverage differs from the declared domains"
            )
        }
    }

    private func inactiveSequentialControls(
        module: GateModule,
        configuration: DFTATPGConfiguration
    ) -> [String: Bool] {
        var portsByID: [String: RTLPort] = [:]
        for port in module.ports where portsByID[port.id] == nil {
            portsByID[port.id] = port
        }
        var portByNetID: [String: RTLPort] = [:]
        for binding in module.portBindings {
            guard portByNetID[binding.netID] == nil,
                  let port = portsByID[binding.portID] else {
                continue
            }
            portByNetID[binding.netID] = port
        }
        var assignments: [String: Bool] = [:]
        for cell in module.cells {
            guard let contract = configuration.sequentialCellContracts.first(
                where: { $0.matches(cellType: cell.type) }
            ) else {
                continue
            }
            for pinName in contract.resetPinNames {
                guard let netID = cell.pins.first(where: {
                    $0.name == pinName
                })?.netID, let port = portByNetID[netID] else {
                    continue
                }
                assignments[port.name] = contract.resetPolarity == .activeLow
            }
            for pinName in contract.setPinNames {
                guard let netID = cell.pins.first(where: {
                    $0.name == pinName
                })?.netID, let port = portByNetID[netID] else {
                    continue
                }
                assignments[port.name] = contract.setPolarity == .activeLow
            }
        }
        return assignments
    }

    private func compactPatternBits(
        assignment: Int,
        exhaustiveBitCount: Int,
        length: Int
    ) -> String {
        var bits = Array(repeating: "0", count: length)
        for index in 0..<min(exhaustiveBitCount, length) {
            bits[index] = (assignment & (1 << index)) == 0 ? "0" : "1"
        }
        return bits.joined()
    }

    private func binaryString<Values: Sequence>(
        _ values: Values
    ) -> String where Values.Element == Bool {
        values.map { $0 ? "1" : "0" }.joined()
    }
}

private struct RealizedScanDetectionCandidate {
    var assignment: Int
    var initialState: [String: Bool]
    var captureInputs: [String: Bool]
    var goodResult: GateLevelSequentialSimulationResult
}
