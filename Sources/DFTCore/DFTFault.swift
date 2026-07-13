import Foundation

public struct DFTFault: Sendable, Hashable, Codable {
    public var id: String
    public var family: DFTFaultFamily
    public var location: String
    public var polarity: DFTSignalLevel?
    public var stuckAtValue: DFTStuckAtValue?
    public var transitionDirection: DFTTransitionDirection?
    public var processFamily: String?

    public init(
        id: String,
        family: DFTFaultFamily,
        location: String,
        polarity: DFTSignalLevel? = nil,
        stuckAtValue: DFTStuckAtValue? = nil,
        transitionDirection: DFTTransitionDirection? = nil,
        processFamily: String? = nil
    ) {
        self.id = id
        self.family = family
        self.location = location
        self.polarity = polarity
        self.stuckAtValue = stuckAtValue
        self.transitionDirection = transitionDirection
        self.processFamily = processFamily
    }
}
