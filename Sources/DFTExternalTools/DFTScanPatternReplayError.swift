import Foundation

public enum DFTScanPatternReplayError: Error, LocalizedError, Sendable, Hashable {
    case invalidRequest(String)
    case artifactIntegrityMismatch(path: String)
    case patternDecodeFailed(String)
    case inputDecodeFailed(name: String, message: String)
    case harnessGenerationFailed(String)
    case executableIdentityMismatch(
        implementationID: String,
        expected: String,
        actual: String
    )
    case processFailed(
        implementationID: String,
        exitCode: Int32,
        standardError: String
    )
    case processLaunchFailed(implementationID: String, message: String)
    case processTimedOut(implementationID: String, timeoutSeconds: Double)
    case processCancelled(implementationID: String)
    case goldenReplayMismatch(String)
    case replayOutputInvalid(String)
    case temporaryWorkspaceFailed(String)
    case temporaryWorkspaceCleanupFailed(String)
    case artifactPersistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "DFT scan-pattern replay request is invalid: \(message)"
        case .artifactIntegrityMismatch(let path):
            return "DFT scan-pattern replay artifact failed integrity validation: \(path)"
        case .patternDecodeFailed(let message):
            return "Retained STIL pattern decoding failed: \(message)"
        case .inputDecodeFailed(let name, let message):
            return "Retained DFT replay \(name) decoding failed: \(message)"
        case .harnessGenerationFailed(let message):
            return "DFT replay harness generation failed: \(message)"
        case .executableIdentityMismatch(
            let implementationID,
            let expected,
            let actual
        ):
            return "DFT replay executable \(implementationID) digest \(actual) does not match \(expected)."
        case .processFailed(
            let implementationID,
            let exitCode,
            let standardError
        ):
            return "DFT replay implementation \(implementationID) exited with code \(exitCode): \(standardError)"
        case .processLaunchFailed(let implementationID, let message):
            return "DFT replay implementation \(implementationID) failed to launch: \(message)"
        case .processTimedOut(let implementationID, let timeoutSeconds):
            return "DFT replay implementation \(implementationID) timed out after \(timeoutSeconds) seconds."
        case .processCancelled(let implementationID):
            return "DFT replay implementation \(implementationID) was cancelled."
        case .goldenReplayMismatch(let message):
            return "Golden DFT pattern replay failed: \(message)"
        case .replayOutputInvalid(let message):
            return "DFT pattern replay output is invalid: \(message)"
        case .temporaryWorkspaceFailed(let message):
            return "DFT replay temporary workspace failed: \(message)"
        case .temporaryWorkspaceCleanupFailed(let message):
            return "DFT replay temporary workspace cleanup failed: \(message)"
        case .artifactPersistenceFailed(let message):
            return "DFT replay evidence persistence failed: \(message)"
        }
    }
}
