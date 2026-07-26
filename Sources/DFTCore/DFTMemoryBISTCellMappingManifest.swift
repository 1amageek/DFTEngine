import Foundation

public struct DFTMemoryBISTCellMappingManifest: Sendable, Hashable, Codable {
    public var processID: String
    public var pdkDigest: String
    public var controllerCellType: String
    public var inputMuxCellType: String
    public var responseCompactorCellType: String
    public var signatureRegisterCellType: String
    public var supportedMacroTypes: [String]
    public var supportedAlgorithmIDs: [String]

    public init(
        processID: String,
        pdkDigest: String,
        controllerCellType: String,
        inputMuxCellType: String,
        responseCompactorCellType: String,
        signatureRegisterCellType: String,
        supportedMacroTypes: [String],
        supportedAlgorithmIDs: [String]
    ) {
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.controllerCellType = controllerCellType
        self.inputMuxCellType = inputMuxCellType
        self.responseCompactorCellType = responseCompactorCellType
        self.signatureRegisterCellType = signatureRegisterCellType
        self.supportedMacroTypes = supportedMacroTypes.sorted()
        self.supportedAlgorithmIDs = supportedAlgorithmIDs.sorted()
    }
}
