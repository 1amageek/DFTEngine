import Foundation

public enum DFTCellLibraryTimingError: Error, LocalizedError, Sendable, Hashable {
    case bindingGroupMissing(String)
    case timingCellMissing(bindingID: String, cellName: String)
    case requiredPinMissing(bindingID: String, pinName: String)
    case sequentialModelMissing(bindingID: String, cellName: String)
    case sequentialPinMismatch(bindingID: String, expected: String, actual: String)
    case clockToQArcMissing(bindingID: String, cellName: String)

    public var errorDescription: String? {
        switch self {
        case .bindingGroupMissing(let bindingID):
            return "DFT binding \(bindingID) has no legal replacement group."
        case .timingCellMissing(let bindingID, let cellName):
            return "DFT binding \(bindingID) has no timing cell named \(cellName)."
        case .requiredPinMissing(let bindingID, let pinName):
            return "DFT binding \(bindingID) requires timing pin \(pinName), but the timing cell does not provide it."
        case .sequentialModelMissing(let bindingID, let cellName):
            return "DFT binding \(bindingID) timing cell \(cellName) has no sequential model."
        case .sequentialPinMismatch(let bindingID, let expected, let actual):
            return "DFT binding \(bindingID) sequential pin mismatch: expected \(expected), got \(actual)."
        case .clockToQArcMissing(let bindingID, let cellName):
            return "DFT binding \(bindingID) timing cell \(cellName) has no clock-to-Q arc."
        }
    }
}
