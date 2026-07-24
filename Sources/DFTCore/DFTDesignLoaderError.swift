import Foundation
import CircuiteFoundation

public enum DFTDesignLoaderError: Error, LocalizedError, Sendable, Hashable {
    case unsupportedFormat(ArtifactFormat)
    case invalidPath(String)
    case readFailed(path: String, message: String)
    case byteCountMismatch(path: String, expected: Int64, actual: Int64)
    case artifactDigestMismatch(path: String, expected: String, actual: String)
    case snapshotDecodeFailed(path: String, message: String)
    case designDigestMismatch(expected: String, actual: String)
    case topDesignMismatch(expected: String, actual: String)
    case gateDesignMissing
    case gateDesignInvalid([String])

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "DFT design loader does not support \(format.rawValue) design artifacts."
        case .invalidPath(let path):
            return "DFT design artifact path is not a safe project-relative path: \(path)."
        case .readFailed(let path, let message):
            return "Could not read DFT design artifact \(path): \(message)"
        case .byteCountMismatch(let path, let expected, let actual):
            return "DFT design artifact \(path) has \(actual) bytes; expected \(expected)."
        case .artifactDigestMismatch(let path, let expected, let actual):
            return "DFT design artifact \(path) digest \(actual) does not match \(expected)."
        case .snapshotDecodeFailed(let path, let message):
            return "Could not decode LogicDesignSnapshot at \(path): \(message)"
        case .designDigestMismatch(let expected, let actual):
            return "Design digest \(actual) does not match the request digest \(expected)."
        case .topDesignMismatch(let expected, let actual):
            return "Design top \(actual) does not match the requested top \(expected)."
        case .gateDesignMissing:
            return "DFT scan insertion requires a gate-level design in the LogicDesignSnapshot."
        case .gateDesignInvalid(let diagnostics):
            return "DFT design is not a valid canonical gate design: \(diagnostics.joined(separator: "; "))"
        }
    }
}
