import Foundation

public enum DFTOracleCorrelationStatus: String, Sendable, Hashable, Codable {
    case correlated
    case mismatched
    case incomplete
}
