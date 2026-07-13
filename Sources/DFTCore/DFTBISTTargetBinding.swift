import Foundation

public struct DFTBISTTargetBinding: Sendable, Hashable, Codable {
    public var instanceName: String
    public var patternInputPinNames: [String]
    public var responseOutputPinNames: [String]

    public init(
        instanceName: String,
        patternInputPinNames: [String],
        responseOutputPinNames: [String]
    ) {
        self.instanceName = instanceName
        self.patternInputPinNames = patternInputPinNames
        self.responseOutputPinNames = responseOutputPinNames
    }
}
