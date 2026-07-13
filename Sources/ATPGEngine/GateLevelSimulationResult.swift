import Foundation

public struct GateLevelSimulationResult: Sendable, Hashable {
    public var observedValues: [String: Bool]

    public init(observedValues: [String: Bool]) {
        self.observedValues = observedValues
    }
}
