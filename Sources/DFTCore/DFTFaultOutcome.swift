import Foundation

public struct DFTFaultOutcome: Sendable, Hashable, Codable {
    public var faultID: String
    public var status: DFTFaultResultStatus
    public var patternID: String?
    public var modelID: String?
    public var verificationID: String?
    public var processCaptureTiming: DFTProcessCaptureTiming?
    public var reason: String

    public init(
        faultID: String,
        status: DFTFaultResultStatus,
        patternID: String? = nil,
        modelID: String? = nil,
        verificationID: String? = nil,
        processCaptureTiming: DFTProcessCaptureTiming? = nil,
        reason: String
    ) {
        self.faultID = faultID
        self.status = status
        self.patternID = patternID
        self.modelID = modelID
        self.verificationID = verificationID
        self.processCaptureTiming = processCaptureTiming
        self.reason = reason
    }
}
