import Foundation

public struct DFTMemoryBISTBinding: Sendable, Hashable, Codable {
    public var instanceName: String
    public var macroType: String
    public var clockPinName: String
    public var resetPinName: String?
    public var enablePinName: String
    public var writeEnablePinName: String
    public var addressPinNames: [String]
    public var dataInputPinNames: [String]
    public var dataOutputPinNames: [String]
    public var testModePinName: String?
    public var algorithmID: String

    public init(
        instanceName: String,
        macroType: String,
        clockPinName: String,
        resetPinName: String? = nil,
        enablePinName: String,
        writeEnablePinName: String,
        addressPinNames: [String],
        dataInputPinNames: [String],
        dataOutputPinNames: [String],
        testModePinName: String? = nil,
        algorithmID: String
    ) {
        self.instanceName = instanceName
        self.macroType = macroType
        self.clockPinName = clockPinName
        self.resetPinName = resetPinName
        self.enablePinName = enablePinName
        self.writeEnablePinName = writeEnablePinName
        self.addressPinNames = addressPinNames
        self.dataInputPinNames = dataInputPinNames
        self.dataOutputPinNames = dataOutputPinNames
        self.testModePinName = testModePinName
        self.algorithmID = algorithmID
    }

    public var isStructurallyComplete: Bool {
        !instanceName.isEmpty
            && !macroType.isEmpty
            && !clockPinName.isEmpty
            && !enablePinName.isEmpty
            && !writeEnablePinName.isEmpty
            && !addressPinNames.isEmpty
            && !dataInputPinNames.isEmpty
            && !dataOutputPinNames.isEmpty
            && !algorithmID.isEmpty
    }
}
