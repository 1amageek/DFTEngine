import DFTCore

public struct DFTScanPatternExchangeConverter:
    DFTScanPatternExchangeConverting
{
    private let validator: any DFTPatternExchangeValidating

    public init(
        validator: any DFTPatternExchangeValidating =
            DFTPatternExchangeValidator()
    ) {
        self.validator = validator
    }

    public func program(
        from plan: DFTScanPatternExecutionPlan,
        name: String
    ) throws -> DFTPatternExchangeProgram {
        guard plan.schemaVersion
                == DFTScanPatternExecutionPlan.currentSchemaVersion,
              isSHA256(plan.scanImplementationDigest),
              isSHA256(plan.transformedDesignDigest),
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              plan.clockPeriodPicoseconds > 1,
              !plan.patterns.isEmpty,
              let first = plan.patterns.first else {
            throw DFTPatternExchangeError.invalidScanExecutionPlan(
                "schema, timing and pattern collection must be complete"
            )
        }
        let inputNames = Set(first.capture.primaryInputs.keys)
        let outputNames = Set(first.capture.expectedPrimaryOutputs.keys)
        guard inputNames.contains(plan.clockSignal),
              inputNames.contains(plan.scanEnableSignal),
              inputNames.contains(plan.testModeSignal),
              plan.clockSignal != plan.scanEnableSignal,
              plan.clockSignal != plan.testModeSignal,
              plan.scanEnableSignal != plan.testModeSignal,
              inputNames.isDisjoint(with: outputNames) else {
            throw DFTPatternExchangeError.invalidScanExecutionPlan(
                "capture signals have missing controls or conflicting directions"
            )
        }
        let referenceTopology = try topology(for: first)
        let patternIDs = plan.patterns.map(\.id)
        let scanInputNames = Set(referenceTopology.map(\.scanInSignal))
        let scanOutputNames = Set(referenceTopology.map(\.scanOutSignal))
        guard patternIDs.allSatisfy({
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }),
              Set(patternIDs).count == patternIDs.count,
              scanInputNames.isSubset(of: inputNames),
              scanOutputNames.isSubset(of: outputNames),
              scanInputNames.isDisjoint(with: scanOutputNames),
              !scanInputNames.contains(plan.clockSignal),
              !scanInputNames.contains(plan.scanEnableSignal),
              !scanInputNames.contains(plan.testModeSignal) else {
            throw DFTPatternExchangeError.invalidScanExecutionPlan(
                "pattern identity and scan signal directions must be exact"
            )
        }
        for pattern in plan.patterns {
            guard Set(pattern.capture.primaryInputs.keys) == inputNames,
                  Set(pattern.capture.expectedPrimaryOutputs.keys)
                    == outputNames,
                  try topology(for: pattern) == referenceTopology else {
                throw DFTPatternExchangeError.invalidScanExecutionPlan(
                    "every pattern must use one stable signal and scan topology"
                )
            }
        }
        let orderedInputs = inputNames.sorted()
        let orderedOutputs = outputNames.sorted()
        let signals = orderedInputs.map {
            DFTPatternSignal(name: $0, direction: .input)
        } + orderedOutputs.map {
            DFTPatternSignal(name: $0, direction: .output)
        }
        let timingName = "scan_cycle"
        let timingSet = DFTPatternTimingSet(
            name: timingName,
            periodPicoseconds: plan.clockPeriodPicoseconds,
            waveforms: signals.map {
                waveform(
                    for: $0,
                    clockSignal: plan.clockSignal,
                    periodPicoseconds: plan.clockPeriodPicoseconds
                )
            }
        )
        let procedures = try plan.patterns.map { pattern in
            DFTPatternProcedure(
                name: procedureName(for: pattern.id),
                cycles: try cycles(
                    for: pattern,
                    plan: plan,
                    inputNames: orderedInputs,
                    outputNames: orderedOutputs,
                    timingName: timingName
                )
            )
        }
        let program = DFTPatternExchangeProgram(
            name: name,
            signals: signals,
            signalGroups: [],
            timingSets: [timingSet],
            procedures: procedures,
            patterns: plan.patterns.map {
                DFTPatternCase(
                    id: $0.id,
                    procedureNames: [procedureName(for: $0.id)]
                )
            }
        )
        try validator.validate(program)
        return program
    }

    private func topology(
        for pattern: DFTScanPatternExecution
    ) throws -> [ScanTopology] {
        let topology = pattern.chains.map {
            ScanTopology(
                chainID: $0.chainID,
                scanInSignal: $0.scanInSignal,
                scanOutSignal: $0.scanOutSignal,
                width: $0.elementOutputNetIDs.count
            )
        }.sorted { $0.chainID < $1.chainID }
        guard !topology.isEmpty,
              Set(topology.map(\.chainID)).count == topology.count,
              Set(topology.map(\.scanInSignal)).count == topology.count,
              Set(topology.map(\.scanOutSignal)).count == topology.count,
              pattern.chains.allSatisfy({
                  !$0.elementOutputNetIDs.isEmpty
                    && $0.loadBits.count == $0.elementOutputNetIDs.count
                    && $0.expectedUnloadBits.count
                        == $0.elementOutputNetIDs.count
                    && $0.loadBits.allSatisfy(isBinary)
                    && $0.expectedUnloadBits.allSatisfy(isBinary)
              }) else {
            throw DFTPatternExchangeError.invalidScanExecutionPlan(
                "scan chains must have unique signals and complete binary vectors"
            )
        }
        return topology
    }

    private func cycles(
        for pattern: DFTScanPatternExecution,
        plan: DFTScanPatternExecutionPlan,
        inputNames: [String],
        outputNames: [String],
        timingName: String
    ) throws -> [DFTPatternCycle] {
        let loadBitsByInput = Dictionary(
            uniqueKeysWithValues: pattern.chains.map {
                ($0.scanInSignal, Array($0.loadBits.utf8))
            }
        )
        let unloadBitsByOutput = Dictionary(
            uniqueKeysWithValues: pattern.chains.map {
                ($0.scanOutSignal, Array($0.expectedUnloadBits.utf8))
            }
        )
        let shiftCount = pattern.chains.map {
            $0.elementOutputNetIDs.count
        }.max() ?? 0
        var cycles: [DFTPatternCycle] = []
        for index in 0..<shiftCount {
            cycles.append(DFTPatternCycle(
                timingSetName: timingName,
                assignments: assignments(
                    inputNames: inputNames,
                    outputNames: outputNames,
                    inputSymbol: { signal in
                        if signal == plan.clockSignal { return "P" }
                        if signal == plan.scanEnableSignal
                            || signal == plan.testModeSignal {
                            return "1"
                        }
                        if let bits = loadBitsByInput[signal] {
                            guard index < bits.count else { return "0" }
                            return bits[index] == 49 ? "1" : "0"
                        }
                        return pattern.capture.primaryInputs[signal] == true
                            ? "1"
                            : "0"
                    },
                    outputSymbol: { _ in "X" }
                )
            ))
        }
        cycles.append(DFTPatternCycle(
            timingSetName: timingName,
            assignments: assignments(
                inputNames: inputNames,
                outputNames: outputNames,
                inputSymbol: { signal in
                    if signal == plan.clockSignal { return "P" }
                    if signal == plan.scanEnableSignal { return "0" }
                    if signal == plan.testModeSignal { return "1" }
                    if loadBitsByInput[signal] != nil { return "0" }
                    return pattern.capture.primaryInputs[signal] == true
                        ? "1"
                        : "0"
                },
                outputSymbol: { signal in
                    pattern.capture.expectedPrimaryOutputs[signal] == true
                        ? "H"
                        : "L"
                }
            )
        ))
        for index in 0..<shiftCount {
            cycles.append(DFTPatternCycle(
                timingSetName: timingName,
                assignments: assignments(
                    inputNames: inputNames,
                    outputNames: outputNames,
                    inputSymbol: { signal in
                        if signal == plan.clockSignal { return "P" }
                        if signal == plan.scanEnableSignal
                            || signal == plan.testModeSignal {
                            return "1"
                        }
                        if loadBitsByInput[signal] != nil { return "0" }
                        return pattern.capture.primaryInputs[signal] == true
                            ? "1"
                            : "0"
                    },
                    outputSymbol: { signal in
                        guard let bits = unloadBitsByOutput[signal] else {
                            return "X"
                        }
                        guard index < bits.count else { return "X" }
                        return bits[index] == 49 ? "H" : "L"
                    }
                )
            ))
        }
        return cycles
    }

    private func assignments(
        inputNames: [String],
        outputNames: [String],
        inputSymbol: (String) -> String,
        outputSymbol: (String) -> String
    ) -> [DFTPatternAssignment] {
        inputNames.map {
            DFTPatternAssignment(target: $0, symbols: inputSymbol($0))
        } + outputNames.map {
            DFTPatternAssignment(target: $0, symbols: outputSymbol($0))
        }
    }

    private func waveform(
        for signal: DFTPatternSignal,
        clockSignal: String,
        periodPicoseconds: UInt64
    ) -> DFTSignalWaveform {
        if signal.direction == .input {
            var symbols = [
                DFTWaveformSymbol(
                    symbol: "0",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: 0,
                            action: .driveLow
                        )
                    ]
                ),
                DFTWaveformSymbol(
                    symbol: "1",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: 0,
                            action: .driveHigh
                        )
                    ]
                ),
            ]
            if signal.name == clockSignal {
                symbols.append(DFTWaveformSymbol(
                    symbol: "P",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: 0,
                            action: .driveLow
                        ),
                        DFTWaveformEvent(
                            offsetPicoseconds: periodPicoseconds / 2,
                            action: .driveHigh
                        ),
                    ]
                ))
            }
            return DFTSignalWaveform(
                signalName: signal.name,
                symbols: symbols
            )
        }
        return DFTSignalWaveform(
            signalName: signal.name,
            symbols: [
                DFTWaveformSymbol(
                    symbol: "L",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: periodPicoseconds / 2,
                            action: .compareLow
                        )
                    ]
                ),
                DFTWaveformSymbol(
                    symbol: "H",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: periodPicoseconds / 2,
                            action: .compareHigh
                        )
                    ]
                ),
                DFTWaveformSymbol(
                    symbol: "X",
                    events: [
                        DFTWaveformEvent(
                            offsetPicoseconds: periodPicoseconds / 2,
                            action: .mask
                        )
                    ]
                ),
            ]
        )
    }

    private func procedureName(for patternID: String) -> String {
        "\(patternID)_procedure"
    }

    private func isBinary(_ character: Character) -> Bool {
        character == "0" || character == "1"
    }

    private func isSHA256(_ value: String) -> Bool {
        value.count == 64 && value.utf8.allSatisfy {
            ($0 >= 48 && $0 <= 57)
                || ($0 >= 65 && $0 <= 70)
                || ($0 >= 97 && $0 <= 102)
        }
    }
}

private struct ScanTopology: Sendable, Hashable {
    var chainID: String
    var scanInSignal: String
    var scanOutSignal: String
    var width: Int
}
