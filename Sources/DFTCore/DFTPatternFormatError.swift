import Foundation

public enum DFTPatternFormatError: Error, LocalizedError, Sendable, Hashable {
    case unsupportedFormat(String)
    case malformedPattern(String)
    case emptyPatternSet

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported DFT pattern format: \(format)."
        case .malformedPattern(let message):
            return "Malformed DFT pattern artifact: \(message)."
        case .emptyPatternSet:
            return "A DFT pattern set must contain at least one pattern."
        }
    }
}
