import Foundation

public enum DFTCapabilityStatus: String, Sendable, Hashable, Codable {
    case available
    case blocked
    case unsupported
}
