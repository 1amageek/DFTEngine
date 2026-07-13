import Foundation
import XcircuitePackage

public enum DFTCellLibraryError: Error, LocalizedError, Sendable, Hashable {
    case unsupportedFormat(XcircuiteFileFormat)
    case invalidPath(String)
    case readFailed(path: String, message: String)
    case byteCountMismatch(path: String, expected: Int64, actual: Int64)
    case artifactDigestMismatch(path: String, expected: String, actual: String)
    case manifestDecodeFailed(path: String, message: String)
    case manifestDigestMismatch(expected: String, actual: String)
    case referenceMismatch(field: String, expected: String, actual: String)
    case invalidManifest(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "DFT cell library loader does not support \(format.rawValue) artifacts."
        case .invalidPath(let path):
            return "DFT cell library path is not a safe project-relative path: \(path)."
        case .readFailed(let path, let message):
            return "Could not read DFT cell library \(path): \(message)"
        case .byteCountMismatch(let path, let expected, let actual):
            return "DFT cell library \(path) has \(actual) bytes; expected \(expected)."
        case .artifactDigestMismatch(let path, let expected, let actual):
            return "DFT cell library \(path) digest \(actual) does not match \(expected)."
        case .manifestDecodeFailed(let path, let message):
            return "Could not decode DFT cell library manifest at \(path): \(message)"
        case .manifestDigestMismatch(let expected, let actual):
            return "DFT cell library manifest digest \(actual) does not match \(expected)."
        case .referenceMismatch(let field, let expected, let actual):
            return "DFT cell library reference \(field) \(actual) does not match \(expected)."
        case .invalidManifest(let message):
            return "DFT cell library manifest is invalid: \(message)"
        }
    }
}
