import Foundation

public struct DFTProcessFaultModelResult: Sendable, Hashable, Codable {
    public var modelID: String
    public var status: DFTFaultResultStatus
    public var patternBits: String?
    public var reason: String

    public init(
        modelID: String,
        status: DFTFaultResultStatus,
        patternBits: String? = nil,
        reason: String
    ) {
        self.modelID = modelID
        self.status = status
        self.patternBits = patternBits
        self.reason = reason
    }
}
