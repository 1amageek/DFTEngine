import Foundation

public struct DFTProcessFaultModelResult: Sendable, Hashable, Codable {
    public var modelID: String
    public var status: DFTFaultResultStatus
    public var patternBits: String?
    public var captureTiming: DFTProcessCaptureTiming?
    public var reason: String

    public init(
        modelID: String,
        status: DFTFaultResultStatus,
        patternBits: String? = nil,
        captureTiming: DFTProcessCaptureTiming? = nil,
        reason: String
    ) {
        self.modelID = modelID
        self.status = status
        self.patternBits = patternBits
        self.captureTiming = captureTiming
        self.reason = reason
    }
}
