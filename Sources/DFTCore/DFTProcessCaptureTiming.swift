import Foundation

public struct DFTProcessCaptureTiming: Sendable, Hashable, Codable {
    public var clockSignal: String
    public var launchEdge: DFTClockEdge
    public var captureEdge: DFTClockEdge
    public var launchToCaptureNanoseconds: Double
    public var sampleOffsetNanoseconds: Double
    public var assumptions: [String]

    public init(
        clockSignal: String,
        launchEdge: DFTClockEdge,
        captureEdge: DFTClockEdge,
        launchToCaptureNanoseconds: Double,
        sampleOffsetNanoseconds: Double,
        assumptions: [String]
    ) {
        self.clockSignal = clockSignal
        self.launchEdge = launchEdge
        self.captureEdge = captureEdge
        self.launchToCaptureNanoseconds = launchToCaptureNanoseconds
        self.sampleOffsetNanoseconds = sampleOffsetNanoseconds
        self.assumptions = assumptions
    }
}
