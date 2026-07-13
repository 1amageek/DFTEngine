import Foundation

public struct DFTScanClock: Sendable, Hashable, Codable {
    public var id: String
    public var signalName: String
    public var periodNanoseconds: Double
    public var dutyCycle: Double
    public var isGenerated: Bool

    public init(
        id: String,
        signalName: String,
        periodNanoseconds: Double,
        dutyCycle: Double = 0.5,
        isGenerated: Bool = false
    ) {
        self.id = id
        self.signalName = signalName
        self.periodNanoseconds = periodNanoseconds
        self.dutyCycle = dutyCycle
        self.isGenerated = isGenerated
    }
}
