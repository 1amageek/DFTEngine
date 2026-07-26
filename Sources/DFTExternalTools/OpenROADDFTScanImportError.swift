import Foundation

public enum OpenROADDFTScanImportError:
    Error,
    LocalizedError,
    Sendable,
    Hashable
{
    case invalidRequest(String)
    case artifactIntegrityMismatch(path: String)
    case inputTextInvalid(name: String)
    case cellLibraryInvalid(String)
    case gateNetlistInvalid(name: String, diagnostics: [String])
    case scanDEFInvalid(String)
    case functionalCellBindingMissing(cellType: String)
    case scanConnectivityInvalid(String)
    case artifactPersistenceFailed(String)

    public var errorDescription: String? {
        switch self {
        case .invalidRequest(let message):
            return "OpenROAD DFT scan import request is invalid: \(message)"
        case .artifactIntegrityMismatch(let path):
            return "OpenROAD DFT scan import artifact failed integrity validation: \(path)"
        case .inputTextInvalid(let name):
            return "OpenROAD DFT scan import \(name) is not valid UTF-8."
        case .cellLibraryInvalid(let message):
            return "OpenROAD DFT scan cell-library manifest is invalid: \(message)"
        case .gateNetlistInvalid(let name, let diagnostics):
            return "OpenROAD DFT \(name) netlist is invalid: \(diagnostics.joined(separator: "; "))"
        case .scanDEFInvalid(let message):
            return "OpenROAD DFT ScanDEF is invalid: \(message)"
        case .functionalCellBindingMissing(let cellType):
            return "OpenROAD DFT source cell \(cellType) has no process scan binding."
        case .scanConnectivityInvalid(let message):
            return "OpenROAD DFT scan connectivity is invalid: \(message)"
        case .artifactPersistenceFailed(let message):
            return "OpenROAD DFT scan import evidence could not be persisted: \(message)"
        }
    }
}
