import Foundation

public enum DFTExternalToolError: Error, LocalizedError, Sendable, Hashable {
    case requestEncodingFailed(String)
    case operationMismatch(expected: String, actual: String)
    case responseDecodingFailed(String)
    case nonZeroExit(implementationID: String, exitCode: Int32, standardError: String)
    case runIDMismatch(expected: String, actual: String)
    case provenanceInputMismatch
    case schemaVersionMismatch(Int)
    case descriptorMismatch(expected: String, actual: String)
    case implementationMismatch(expected: String, actual: String)
    case implementationVersionMismatch(expected: String, actual: String)
    case invalidArtifactReference(path: String, message: String)
    case processFailed(executablePath: String, exitCode: Int32, standardError: String)
    case executableIdentityMismatch(expected: String, actual: String)
    case artifactReaderUnavailable
    case requestFileWriteFailed(String)
    case requestFileCleanupFailed(String)

    public var errorDescription: String? {
        switch self {
        case .requestEncodingFailed(let message):
            return "External DFT request could not be encoded: \(message)."
        case .operationMismatch(let expected, let actual):
            return "External DFT engine requires operation \(expected), but the request declares \(actual)."
        case .responseDecodingFailed(let message):
            return "External DFT response could not be decoded: \(message)."
        case .nonZeroExit(let implementationID, let exitCode, let standardError):
            return "External DFT implementation \(implementationID) exited with code \(exitCode): \(standardError)"
        case .runIDMismatch(let expected, let actual):
            return "External DFT response run ID \(actual) does not match request \(expected)."
        case .provenanceInputMismatch:
            return "External DFT response provenance inputs do not match the request inputs."
        case .schemaVersionMismatch(let version):
            return "External DFT response schema version \(version) is unsupported."
        case .descriptorMismatch(let expected, let actual):
            return "External DFT response engine \(actual) does not match the requested external tool \(expected)."
        case .implementationMismatch(let expected, let actual):
            return "External DFT response implementation \(actual) does not match the requested external tool \(expected)."
        case .implementationVersionMismatch(let expected, let actual):
            return "External DFT response implementation version \(actual) does not match the requested external tool \(expected)."
        case .invalidArtifactReference(let path, let message):
            return "External DFT artifact reference \(path) is invalid: \(message)"
        case .processFailed(let executablePath, let exitCode, let standardError):
            return "External DFT tool \(executablePath) exited with code \(exitCode): \(standardError)"
        case .executableIdentityMismatch(let expected, let actual):
            return "External DFT executable digest \(actual) does not match descriptor \(expected)."
        case .artifactReaderUnavailable:
            return "Completed external DFT results require a digest-verifying artifact reader."
        case .requestFileWriteFailed(let message):
            return "External DFT request file could not be written: \(message)"
        case .requestFileCleanupFailed(let message):
            return "External DFT request file could not be removed: \(message)"
        }
    }
}
