import Foundation

public enum DFTEvidenceMaturity: String, Sendable, Hashable, Codable {
    case smokeObserved
    case corpusObserved
    case oracleCorrelated
    case unassessed
}
