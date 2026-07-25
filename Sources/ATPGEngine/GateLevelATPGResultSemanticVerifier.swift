import DFTCore
import LogicIR

public struct GateLevelATPGResultSemanticVerifier: DFTATPGResultSemanticVerifying {
    public let combinationalSimulator: any GateLevelSimulating
    public let sequentialSimulator: any GateLevelSequentialSimulating
    public let transitionSimulator: any GateLevelTransitionSimulating
    public let faultExtractor: any DFTFaultExtracting

    public init(
        combinationalSimulator: any GateLevelSimulating =
            GateLevelCombinationalSimulator(),
        sequentialSimulator: any GateLevelSequentialSimulating =
            GateLevelSequentialSimulator(),
        transitionSimulator: any GateLevelTransitionSimulating =
            GateLevelTransitionSimulator(),
        faultExtractor: any DFTFaultExtracting = GateLevelFaultExtractor()
    ) {
        self.combinationalSimulator = combinationalSimulator
        self.sequentialSimulator = sequentialSimulator
        self.transitionSimulator = transitionSimulator
        self.faultExtractor = faultExtractor
    }

    public func validate(
        _ result: DFTResult,
        for request: DFTRequest,
        design: LogicDesignSnapshot
    ) async throws {
        guard let configuration = request.atpgConfiguration,
              let patternSet = result.payload.patterns,
              let evidence = result.payload.coverageEvidence else {
            throw mismatch("ATPG patterns or coverage evidence are missing")
        }
        let universe: DFTFaultUniverse
        switch configuration.faultSource ?? .declaredUniverse {
        case .declaredUniverse:
            guard let declaredUniverse = request.faultUniverse else {
                throw mismatch("the declared ATPG fault universe is missing")
            }
            universe = declaredUniverse
        case .gateLevel:
            do {
                universe = try faultExtractor.extract(
                    from: design,
                    reference: request.design
                )
            } catch {
                throw mismatch(
                    "the gate-level fault universe cannot be reproduced: \(error.localizedDescription)"
                )
            }
        }
        let universeDigest = try DFTDeterministicHasher().digest(universe)
        guard universeDigest == evidence.faultUniverseDigest,
              universeDigest == patternSet.faultUniverseDigest else {
            throw mismatch("the replayed fault universe digest does not match ATPG evidence")
        }

        let faultsByID = Dictionary(uniqueKeysWithValues: universe.faults.map { ($0.id, $0) })
        let patternsByID = Dictionary(
            uniqueKeysWithValues: patternSet.patterns.map { ($0.id, $0) }
        )
        let excluded = Set(universe.excludedFaultIDs)
        let activeFaultIDs = Set(universe.faults.map(\.id)).subtracting(excluded)
        guard Set(evidence.outcomes.map(\.faultID)) == activeFaultIDs else {
            throw mismatch("coverage outcomes do not cover the active fault universe exactly")
        }

        for outcome in evidence.outcomes where outcome.status == .detected {
            try Task.checkCancellation()
            guard let fault = faultsByID[outcome.faultID],
                  let patternID = outcome.patternID,
                  let pattern = patternsByID[patternID],
                  pattern.faultIDs.contains(fault.id) else {
                throw mismatch("detected fault \(outcome.faultID) has no matching pattern")
            }
            try replay(
                fault: fault,
                pattern: pattern,
                design: design,
                configuration: configuration
            )
        }
    }

    private func replay(
        fault: DFTFault,
        pattern: DFTTestPattern,
        design: LogicDesignSnapshot,
        configuration: DFTATPGConfiguration
    ) throws {
        guard let gate = design.gate,
              let module = gate.modules.first(where: { $0.name == gate.topModuleName }) else {
            throw mismatch("the ATPG design has no canonical top gate module")
        }
        let inputPorts = module.ports
            .filter { $0.direction == .input }
            .sorted { $0.name < $1.name }
        let bits = Array(pattern.bits)
        guard bits.allSatisfy({ $0 == "0" || $0 == "1" }) else {
            throw mismatch("pattern \(pattern.id) contains a non-binary value")
        }

        switch fault.family {
        case .stuckAt:
            let hasSequentialCells = module.cells.contains(where: isSequential)
            if hasSequentialCells {
                guard let cycleCount = configuration.maximumSequentialCycleCount,
                      cycleCount > 0 else {
                    throw mismatch("sequential ATPG replay requires a positive cycle count")
                }
                let requiredCount = inputPorts.count * cycleCount
                guard bits.count >= requiredCount else {
                    throw mismatch("pattern \(pattern.id) is shorter than its sequential stimulus")
                }
                let cycles = (0..<cycleCount).map { cycle in
                    Dictionary(uniqueKeysWithValues: inputPorts.enumerated().map {
                        index, port in
                        (port.name, bits[(cycle * inputPorts.count) + index] == "1")
                    })
                }
                let good = try sequentialSimulator.simulate(
                    snapshot: design,
                    inputCycles: cycles,
                    initialState: [:],
                    fault: nil,
                    sequentialContracts: configuration.sequentialCellContracts
                )
                let faulty = try sequentialSimulator.simulate(
                    snapshot: design,
                    inputCycles: cycles,
                    initialState: [:],
                    fault: fault,
                    sequentialContracts: configuration.sequentialCellContracts
                )
                guard good.observedValues != faulty.observedValues else {
                    throw mismatch(
                        "pattern \(pattern.id) does not detect fault \(fault.id) during replay"
                    )
                }
            } else {
                guard bits.count >= inputPorts.count else {
                    throw mismatch("pattern \(pattern.id) is shorter than its input stimulus")
                }
                let inputs = Dictionary(uniqueKeysWithValues: inputPorts.enumerated().map {
                    index, port in
                    (port.name, bits[index] == "1")
                })
                let good = try combinationalSimulator.simulate(
                    snapshot: design,
                    inputs: inputs,
                    fault: nil
                )
                let faulty = try combinationalSimulator.simulate(
                    snapshot: design,
                    inputs: inputs,
                    fault: fault
                )
                guard good.observedValues != faulty.observedValues else {
                    throw mismatch(
                        "pattern \(pattern.id) does not detect fault \(fault.id) during replay"
                    )
                }
            }
        case .transition:
            let requiredCount = inputPorts.count * 2
            guard bits.count >= requiredCount else {
                throw mismatch("pattern \(pattern.id) is shorter than its launch/capture stimulus")
            }
            let launch = Dictionary(uniqueKeysWithValues: inputPorts.enumerated().map {
                index, port in
                (port.name, bits[index] == "1")
            })
            let capture = Dictionary(uniqueKeysWithValues: inputPorts.enumerated().map {
                index, port in
                (port.name, bits[inputPorts.count + index] == "1")
            })
            let replay = try transitionSimulator.simulate(
                snapshot: design,
                launchInputs: launch,
                captureInputs: capture,
                fault: fault,
                sequentialContracts: configuration.sequentialCellContracts
            )
            guard let goodCapture = replay.goodCaptureObservedValues,
                  goodCapture != replay.captureObservedValues else {
                throw mismatch(
                    "pattern \(pattern.id) does not detect fault \(fault.id) during replay"
                )
            }
        case .processSpecific:
            throw mismatch(
                "fault \(fault.id) uses \(fault.family.rawValue) semantics without an independent replay verifier"
            )
        }
    }

    private func isSequential(_ cell: GateCell) -> Bool {
        let normalized = cell.type
            .uppercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
        return normalized.hasPrefix("DFF")
            || normalized.hasPrefix("SDFF")
            || normalized.hasPrefix("SCAN")
            || normalized.hasPrefix("LATCH")
    }

    private func mismatch(_ message: String) -> DFTResultSemanticValidationError {
        .semanticMismatch(message)
    }
}
