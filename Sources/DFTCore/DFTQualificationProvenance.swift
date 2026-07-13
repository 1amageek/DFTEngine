import Foundation

public enum DFTQualificationStatus: String, Sendable, Hashable, Codable {
    case smokeChecked
    case corpusChecked
    case oracleCorrelated
    case processQualified
    case unqualified
}
