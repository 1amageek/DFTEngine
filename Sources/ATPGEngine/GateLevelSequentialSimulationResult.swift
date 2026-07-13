import Foundation

public struct GateLevelSequentialSimulationResult: Sendable, Hashable {
    public var observedValues: [[String: Bool]]
    public var netValues: [[String: Bool]]
    public var finalState: [String: Bool]

    public init(
        observedValues: [[String: Bool]],
        finalState: [String: Bool],
        netValues: [[String: Bool]] = []
    ) {
        self.observedValues = observedValues
        self.netValues = netValues
        self.finalState = finalState
    }
}
