import Foundation

public enum DFTOracleCaseCorrelationStatus: String, Sendable, Hashable, Codable {
    case matched
    case mismatched
    case missingObservation
}
