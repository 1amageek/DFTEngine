import Foundation

public struct DFTFaultUniverse: Sendable, Hashable, Codable {
    public var name: String
    public var revision: String
    public var faults: [DFTFault]
    public var excludedFaultIDs: [String]
    public var declaredBy: String

    public init(
        name: String,
        revision: String,
        faults: [DFTFault],
        excludedFaultIDs: [String] = [],
        declaredBy: String
    ) {
        self.name = name
        self.revision = revision
        self.faults = faults
        self.excludedFaultIDs = excludedFaultIDs
        self.declaredBy = declaredBy
    }
}
