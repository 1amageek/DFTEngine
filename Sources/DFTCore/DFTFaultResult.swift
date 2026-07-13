import Foundation

public enum DFTFaultResultStatus: String, Sendable, Hashable, Codable {
    case detected
    case untestable
    case aborted
}
