import Foundation

public enum DFTFoundationBoundaryError: Error, Sendable, Hashable, LocalizedError {
    case missingArtifactID(String)
    case invalidArtifactID(path: String, reason: String)
    case missingDigest(String)
    case invalidDigest(String)
    case missingByteCount(String)
    case invalidByteCount(String)
    case invalidArtifactLocation(String)
    case invalidArtifactKind(path: String, reason: String)
    case invalidArtifactFormat(path: String, reason: String)
    case invalidDiagnosticCode(String)

    public var errorDescription: String? {
        switch self {
        case .missingArtifactID(let path):
            return "DFT artifact is missing a stable artifact ID: \(path)"
        case .invalidArtifactID(let path, let reason):
            return "DFT artifact ID is invalid for \(path): \(reason)"
        case .missingDigest(let path):
            return "DFT artifact is missing a SHA-256 digest: \(path)"
        case .invalidDigest(let path):
            return "DFT artifact has an invalid SHA-256 digest: \(path)"
        case .missingByteCount(let path):
            return "DFT artifact is missing a byte count: \(path)"
        case .invalidByteCount(let path):
            return "DFT artifact has an invalid byte count: \(path)"
        case .invalidArtifactLocation(let path):
            return "DFT artifact has an invalid project-relative location: \(path)"
        case .invalidArtifactKind(let path, let reason):
            return "DFT artifact kind cannot be represented by CircuiteFoundation for \(path): \(reason)"
        case .invalidArtifactFormat(let path, let reason):
            return "DFT artifact format cannot be represented by CircuiteFoundation for \(path): \(reason)"
        case .invalidDiagnosticCode(let code):
            return "DFT diagnostic code cannot be represented by CircuiteFoundation: \(code)"
        }
    }
}
