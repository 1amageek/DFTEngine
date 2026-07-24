import Foundation

public enum DFTConstraintError: Error, LocalizedError, Sendable, Hashable {
    case invalidPath(String)
    case readFailed(String)
    case identityMismatch(String)
    case loaderUnavailable
    case modeMissing
    case modeSetMismatch(expected: [String], actual: [String])
    case conflictingCaseAnalysis(modeID: String, signal: String)
    case clockMissing(modeID: String, signal: String)
    case testSignalNotAsserted(modeID: String, signal: String)

    public var errorDescription: String? {
        switch self {
        case .invalidPath(let path):
            "DFT constraint path is invalid: \(path)."
        case .readFailed(let message):
            "DFT constraints could not be read: \(message)."
        case .identityMismatch(let path):
            "DFT constraint artifact identity does not match \(path)."
        case .loaderUnavailable:
            "DFT constraint loading is unavailable for this execution path."
        case .modeMissing:
            "DFT constraints contain no declared analysis mode."
        case .modeSetMismatch(let expected, let actual):
            "DFT constraint modes \(actual) do not exactly match requested modes \(expected)."
        case .conflictingCaseAnalysis(let modeID, let signal):
            "DFT constraint mode \(modeID) assigns conflicting values to \(signal)."
        case .clockMissing(let modeID, let signal):
            "DFT constraint mode \(modeID) does not declare clock \(signal)."
        case .testSignalNotAsserted(let modeID, let signal):
            "DFT constraint mode \(modeID) does not assert test signal \(signal)."
        }
    }
}
