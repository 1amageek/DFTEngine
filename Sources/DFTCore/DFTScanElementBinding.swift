import Foundation

public struct DFTScanElementBinding: Sendable, Hashable, Codable {
    public var position: Int
    public var cellID: String
    public var instanceName: String
    public var cellType: String
    public var dataPinName: String
    public var dataNetID: String
    public var outputPinName: String
    public var outputNetID: String
    public var clockPinName: String
    public var clockNetID: String
    public var scanInPinName: String
    public var scanInNetID: String
    public var scanEnablePinName: String
    public var scanEnableNetID: String
    public var testModePinName: String?
    public var testModeNetID: String?

    public init(
        position: Int,
        cellID: String,
        instanceName: String,
        cellType: String,
        dataPinName: String,
        dataNetID: String,
        outputPinName: String,
        outputNetID: String,
        clockPinName: String,
        clockNetID: String,
        scanInPinName: String,
        scanInNetID: String,
        scanEnablePinName: String,
        scanEnableNetID: String,
        testModePinName: String?,
        testModeNetID: String?
    ) {
        self.position = position
        self.cellID = cellID
        self.instanceName = instanceName
        self.cellType = cellType
        self.dataPinName = dataPinName
        self.dataNetID = dataNetID
        self.outputPinName = outputPinName
        self.outputNetID = outputNetID
        self.clockPinName = clockPinName
        self.clockNetID = clockNetID
        self.scanInPinName = scanInPinName
        self.scanInNetID = scanInNetID
        self.scanEnablePinName = scanEnablePinName
        self.scanEnableNetID = scanEnableNetID
        self.testModePinName = testModePinName
        self.testModeNetID = testModeNetID
    }
}
