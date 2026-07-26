import CircuiteFoundation
import Foundation

public struct DFTMemoryBISTCellMapping: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var processID: String
    public var pdkDigest: String
    public var controllerCellType: String
    public var inputMuxCellType: String
    public var responseCompactorCellType: String
    public var signatureRegisterCellType: String
    public var supportedMacroTypes: [String]
    public var supportedAlgorithmIDs: [String]

    public init(
        artifact: ArtifactReference,
        processID: String,
        pdkDigest: String,
        controllerCellType: String,
        inputMuxCellType: String,
        responseCompactorCellType: String,
        signatureRegisterCellType: String,
        supportedMacroTypes: [String],
        supportedAlgorithmIDs: [String]
    ) {
        self.artifact = artifact
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.controllerCellType = controllerCellType
        self.inputMuxCellType = inputMuxCellType
        self.responseCompactorCellType = responseCompactorCellType
        self.signatureRegisterCellType = signatureRegisterCellType
        self.supportedMacroTypes = supportedMacroTypes.sorted()
        self.supportedAlgorithmIDs = supportedAlgorithmIDs.sorted()
    }

    public var manifest: DFTMemoryBISTCellMappingManifest {
        DFTMemoryBISTCellMappingManifest(
            processID: processID,
            pdkDigest: pdkDigest,
            controllerCellType: controllerCellType,
            inputMuxCellType: inputMuxCellType,
            responseCompactorCellType: responseCompactorCellType,
            signatureRegisterCellType: signatureRegisterCellType,
            supportedMacroTypes: supportedMacroTypes,
            supportedAlgorithmIDs: supportedAlgorithmIDs
        )
    }
}
