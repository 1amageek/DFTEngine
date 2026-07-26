import CircuiteFoundation
import Foundation

public enum DFTScanImplementationLoaderError:
    Error,
    LocalizedError,
    Sendable,
    Hashable
{
    case unsupportedFormat(ArtifactFormat)
    case byteCountMismatch(path: String, expected: UInt64, actual: UInt64)
    case artifactDigestMismatch(path: String, expected: String, actual: String)
    case decodeFailed(path: String, message: String)
    case transformedDesignDigestMismatch(expected: String, actual: String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            "Scan implementation loading requires canonical JSON, not \(format.rawValue)."
        case .byteCountMismatch(let path, let expected, let actual):
            "Scan implementation \(path) has \(actual) bytes; expected \(expected)."
        case .artifactDigestMismatch(let path, let expected, let actual):
            "Scan implementation \(path) digest \(actual) does not match \(expected)."
        case .decodeFailed(let path, let message):
            "Could not decode scan implementation \(path): \(message)"
        case .transformedDesignDigestMismatch(let expected, let actual):
            "Scan implementation design digest \(actual) does not match \(expected)."
        }
    }
}
