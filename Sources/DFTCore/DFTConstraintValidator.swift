import TimingCore

public struct DFTConstraintValidator: Sendable {
    public init() {}

    public func validate(
        _ constraints: [TimingConstraintSet],
        request: DFTRequest
    ) throws {
        guard !constraints.isEmpty else {
            throw DFTConstraintError.modeMissing
        }
        let expectedModes = request.constraints.modeIDs.sorted()
        let actualModes = constraints.map(\.modeID).sorted()
        guard expectedModes == actualModes,
              Set(actualModes).count == actualModes.count else {
            throw DFTConstraintError.modeSetMismatch(
                expected: expectedModes,
                actual: actualModes
            )
        }
        for constraint in constraints {
            try validateCaseAnalysisConsistency(constraint)
            if let architecture = request.scanArchitecture {
                for clock in architecture.clocks where !constraint.clocks.contains(where: {
                    $0.name == clock.signalName || $0.source == clock.signalName
                }) {
                    throw DFTConstraintError.clockMissing(
                        modeID: constraint.modeID,
                        signal: clock.signalName
                    )
                }
                try requireAsserted(
                    architecture.testModeSignal,
                    constraint: constraint
                )
                if request.operation != .bist {
                    try requireAsserted(
                        architecture.scanEnableSignal,
                        constraint: constraint
                    )
                }
            } else if let configuration = request.bistConfiguration {
                if let clockSignal = configuration.clockSignal,
                   !constraint.clocks.contains(where: {
                       $0.name == clockSignal || $0.source == clockSignal
                   }) {
                    throw DFTConstraintError.clockMissing(
                        modeID: constraint.modeID,
                        signal: clockSignal
                    )
                }
                if let testModeSignal = configuration.testModeSignal
                    ?? request.testIntent?.testModeSignal {
                    try requireAsserted(
                        testModeSignal,
                        constraint: constraint
                    )
                }
            }
        }
    }

    private func requireAsserted(
        _ signal: String,
        constraint: TimingConstraintSet
    ) throws {
        guard constraint.caseAnalyses.contains(where: {
            $0.target == signal && $0.value == .one
        }) else {
            throw DFTConstraintError.testSignalNotAsserted(
                modeID: constraint.modeID,
                signal: signal
            )
        }
    }

    private func validateCaseAnalysisConsistency(
        _ constraint: TimingConstraintSet
    ) throws {
        let grouped = Dictionary(grouping: constraint.caseAnalyses, by: \.target)
        if let conflict = grouped.first(where: {
            Set($0.value.map(\.value)).count > 1
        }) {
            throw DFTConstraintError.conflictingCaseAnalysis(
                modeID: constraint.modeID,
                signal: conflict.key
            )
        }
    }
}
