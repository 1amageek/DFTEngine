import Foundation

public enum DFTOracleArtifactError: Error, LocalizedError, Sendable, Hashable {
    case invalidReference(String)
    case missingArtifactID(String)
    case missingDigest(String)
    case invalidDigest(String)
    case missingByteCount(String)
    case invalidByteCount(String)
    case readFailed(path: String, message: String)
    case byteCountMismatch(path: String, expected: Int64, actual: Int64)
    case digestMismatch(path: String, expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .invalidReference(let message):
            return "DFT oracle artifact reference is invalid: " + message
        case .missingArtifactID(let path):
            return "DFT oracle artifact \(path) has no stable artifact ID."
        case .missingDigest(let path):
            return "DFT oracle artifact \(path) has no SHA-256 digest."
        case .invalidDigest(let path):
            return "DFT oracle artifact \(path) has an invalid SHA-256 digest."
        case .missingByteCount(let path):
            return "DFT oracle artifact \(path) has no byte count."
        case .invalidByteCount(let path):
            return "DFT oracle artifact \(path) has an invalid byte count."
        case .readFailed(let path, let message):
            return "DFT oracle artifact " + path + " could not be read: " + message
        case .byteCountMismatch(let path, let expected, let actual):
            return "DFT oracle artifact " + path + " has byte count " + String(actual) + ", expected " + String(expected) + "."
        case .digestMismatch(let path, let expected, let actual):
            return "DFT oracle artifact " + path + " has digest " + actual + ", expected " + expected + "."
        }
    }
}
