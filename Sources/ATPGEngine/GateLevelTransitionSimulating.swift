import DFTCore
import LogicIR

public protocol GateLevelTransitionSimulating: Sendable {
    func simulate(
        snapshot: LogicDesignSnapshot,
        launchInputs: [String: Bool],
        captureInputs: [String: Bool],
        fault: DFTFault
    ) throws -> GateLevelTransitionSimulationResult

    func simulate(
        snapshot: LogicDesignSnapshot,
        launchInputs: [String: Bool],
        captureInputs: [String: Bool],
        fault: DFTFault,
        sequentialContracts: [DFTSequentialCellContract]
    ) throws -> GateLevelTransitionSimulationResult
}

public extension GateLevelTransitionSimulating {
    func simulate(
        snapshot: LogicDesignSnapshot,
        launchInputs: [String: Bool],
        captureInputs: [String: Bool],
        fault: DFTFault,
        sequentialContracts: [DFTSequentialCellContract]
    ) throws -> GateLevelTransitionSimulationResult {
        try simulate(
            snapshot: snapshot,
            launchInputs: launchInputs,
            captureInputs: captureInputs,
            fault: fault
        )
    }
}
