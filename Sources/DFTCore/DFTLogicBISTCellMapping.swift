import CircuiteFoundation
import Foundation

public struct DFTLogicBISTCellMapping: Sendable, Hashable, Codable {
    public var artifact: ArtifactReference
    public var processID: String
    public var pdkDigest: String
    public var controllerCellType: String
    public var inputMuxCellType: String
    public var responseCaptureCellType: String
    public var responseCompactorCellType: String
    public var signatureRegisterCellType: String
    public var prpgPolynomialTaps: [Int]
    public var misrPolynomialTaps: [Int]
    public var expectedSignature: String

    public init(
        artifact: ArtifactReference,
        processID: String,
        pdkDigest: String,
        controllerCellType: String,
        inputMuxCellType: String,
        responseCaptureCellType: String,
        responseCompactorCellType: String,
        signatureRegisterCellType: String,
        prpgPolynomialTaps: [Int],
        misrPolynomialTaps: [Int],
        expectedSignature: String
    ) {
        self.artifact = artifact
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.controllerCellType = controllerCellType
        self.inputMuxCellType = inputMuxCellType
        self.responseCaptureCellType = responseCaptureCellType
        self.responseCompactorCellType = responseCompactorCellType
        self.signatureRegisterCellType = signatureRegisterCellType
        self.prpgPolynomialTaps = prpgPolynomialTaps.sorted()
        self.misrPolynomialTaps = misrPolynomialTaps.sorted()
        self.expectedSignature = expectedSignature
    }
}
