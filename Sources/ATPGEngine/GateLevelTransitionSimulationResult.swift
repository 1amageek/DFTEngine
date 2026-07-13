import Foundation

public struct GateLevelTransitionSimulationResult: Sendable, Hashable {
    public var launchObservedValues: [String: Bool]
    public var captureObservedValues: [String: Bool]
    public var goodCaptureObservedValues: [String: Bool]?

    public init(
        launchObservedValues: [String: Bool],
        captureObservedValues: [String: Bool],
        goodCaptureObservedValues: [String: Bool]? = nil
    ) {
        self.launchObservedValues = launchObservedValues
        self.captureObservedValues = captureObservedValues
        self.goodCaptureObservedValues = goodCaptureObservedValues
    }
}
