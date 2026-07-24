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
        if let architecture = request.scanArchitecture {
            let clocks = constraints.flatMap(\.clocks)
            for clock in architecture.clocks where !clocks.contains(where: {
                $0.name == clock.signalName || $0.source == clock.signalName
            }) {
                throw DFTConstraintError.clockMissing(clock.signalName)
            }
            try requireAsserted(
                architecture.testModeSignal,
                constraints: constraints
            )
            if request.operation != .bist {
                try requireAsserted(
                    architecture.scanEnableSignal,
                    constraints: constraints
                )
            }
        } else if let configuration = request.bistConfiguration {
            if let clockSignal = configuration.clockSignal {
                let clocks = constraints.flatMap(\.clocks)
                guard clocks.contains(where: {
                    $0.name == clockSignal || $0.source == clockSignal
                }) else {
                    throw DFTConstraintError.clockMissing(clockSignal)
                }
            }
            if let testModeSignal = configuration.testModeSignal
                ?? request.testIntent?.testModeSignal {
                try requireAsserted(testModeSignal, constraints: constraints)
            }
        }
    }

    private func requireAsserted(
        _ signal: String,
        constraints: [TimingConstraintSet]
    ) throws {
        guard constraints.contains(where: { constraint in
            constraint.caseAnalyses.contains {
                $0.target == signal && $0.value == .one
            }
        }) else {
            throw DFTConstraintError.testSignalNotAsserted(signal)
        }
    }
}
