import Foundation

public enum DFTDesignDiffDomain: String, Sendable, Hashable, Codable {
    case circuit
    case layout
    case timing
    case verification
    case dft
}
