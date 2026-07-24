import Foundation

public struct DFTBISTStructure: Sendable, Hashable, Codable {
    public var name: String
    public var kind: DFTBISTKind
    public var controllerCellName: String
    public var targetInstances: [String]
    public var patternCount: Int
    public var signatureRegisterName: String
    public var seed: UInt64
    public var testModeSignal: String
    public var logicCellMapping: DFTLogicBISTCellMapping?

    public init(
        name: String,
        kind: DFTBISTKind,
        controllerCellName: String,
        targetInstances: [String],
        patternCount: Int,
        signatureRegisterName: String,
        seed: UInt64,
        testModeSignal: String,
        logicCellMapping: DFTLogicBISTCellMapping? = nil
    ) {
        self.name = name
        self.kind = kind
        self.controllerCellName = controllerCellName
        self.targetInstances = targetInstances
        self.patternCount = patternCount
        self.signatureRegisterName = signatureRegisterName
        self.seed = seed
        self.testModeSignal = testModeSignal
        self.logicCellMapping = logicCellMapping
    }
}
