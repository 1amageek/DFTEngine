import DFTCore
import LogicIR

public protocol GateLevelSequentialSimulating: Sendable {
    func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool],
        fault: DFTFault?
    ) throws -> GateLevelSequentialSimulationResult

    func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool],
        fault: DFTFault?,
        sequentialContracts: [DFTSequentialCellContract]
    ) throws -> GateLevelSequentialSimulationResult

    func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool],
        fault: DFTFault?,
        sequentialContracts: [DFTSequentialCellContract],
        transitionFault: DFTFault?,
        transitionHoldValue: Bool?
    ) throws -> GateLevelSequentialSimulationResult
}

public extension GateLevelSequentialSimulating {
    func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool],
        fault: DFTFault?,
        sequentialContracts: [DFTSequentialCellContract]
    ) throws -> GateLevelSequentialSimulationResult {
        try simulate(
            snapshot: snapshot,
            inputCycles: inputCycles,
            initialState: initialState,
            fault: fault,
            sequentialContracts: sequentialContracts,
            transitionFault: nil,
            transitionHoldValue: nil
        )
    }

    func simulate(
        snapshot: LogicDesignSnapshot,
        inputCycles: [[String: Bool]],
        initialState: [String: Bool],
        fault: DFTFault?,
        sequentialContracts: [DFTSequentialCellContract],
        transitionFault: DFTFault?,
        transitionHoldValue: Bool?
    ) throws -> GateLevelSequentialSimulationResult {
        try simulate(
            snapshot: snapshot,
            inputCycles: inputCycles,
            initialState: initialState,
            fault: fault,
            sequentialContracts: sequentialContracts
        )
    }
}
