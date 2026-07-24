import Foundation

public struct DFTBISTConfiguration: Sendable, Hashable, Codable {
    public var name: String
    public var kind: DFTBISTKind
    public var controllerCellName: String
    public var targetInstances: [String]
    public var patternCount: Int
    public var signatureRegisterName: String
    public var randomSeed: UInt64?
    public var testModeSignal: String?
    public var clockSignal: String?
    public var targetBindings: [DFTBISTTargetBinding]?
    public var memoryBindings: [DFTMemoryBISTBinding]?
    public var logicCellMapping: DFTLogicBISTCellMapping?

    public init(
        name: String,
        kind: DFTBISTKind,
        controllerCellName: String,
        targetInstances: [String],
        patternCount: Int,
        signatureRegisterName: String,
        randomSeed: UInt64? = nil,
        testModeSignal: String? = nil,
        clockSignal: String? = nil,
        targetBindings: [DFTBISTTargetBinding]? = nil,
        memoryBindings: [DFTMemoryBISTBinding]? = nil,
        logicCellMapping: DFTLogicBISTCellMapping? = nil
    ) {
        self.name = name
        self.kind = kind
        self.controllerCellName = controllerCellName
        self.targetInstances = targetInstances
        self.patternCount = patternCount
        self.signatureRegisterName = signatureRegisterName
        self.randomSeed = randomSeed
        self.testModeSignal = testModeSignal
        self.clockSignal = clockSignal
        self.targetBindings = targetBindings
        self.memoryBindings = memoryBindings
        self.logicCellMapping = logicCellMapping
    }
}
