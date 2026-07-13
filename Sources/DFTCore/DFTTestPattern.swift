import Foundation

public struct DFTTestPattern: Sendable, Hashable, Codable {
    public var id: String
    public var bits: String
    public var faultIDs: [String]

    public init(id: String, bits: String, faultIDs: [String]) {
        self.id = id
        self.bits = bits
        self.faultIDs = faultIDs
    }
}
