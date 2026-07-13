import Foundation

public enum DFTFaultFamily: String, Sendable, Hashable, Codable {
    case stuckAt
    case transition
    case processSpecific
}
