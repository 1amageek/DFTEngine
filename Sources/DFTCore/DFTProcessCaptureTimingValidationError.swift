import Foundation

public enum DFTProcessCaptureTimingValidationError: Error, LocalizedError, Sendable, Hashable {
    case clockNotDeclared(String)
    case launchToCaptureInvalid(Double)
    case sampleOffsetInvalid(Double)
    case assumptionsMissing

    public var errorDescription: String? {
        switch self {
        case .clockNotDeclared(let signal):
            "Process capture timing references undeclared DFT clock \(signal)."
        case .launchToCaptureInvalid(let value):
            "Process launch-to-capture interval is invalid: \(value) ns."
        case .sampleOffsetInvalid(let value):
            "Process capture sample offset is invalid: \(value) ns."
        case .assumptionsMissing:
            "Process capture timing requires non-empty assumptions."
        }
    }
}
