import Foundation

public struct DFTScanChainStimulus: Sendable, Hashable, Codable {
    public var chainID: String
    public var scanInSignal: String
    public var scanOutSignal: String
    public var elementOutputNetIDs: [String]
    public var loadBits: String
    public var expectedUnloadBits: String

    public init(
        chainID: String,
        scanInSignal: String,
        scanOutSignal: String,
        elementOutputNetIDs: [String],
        loadBits: String,
        expectedUnloadBits: String
    ) {
        self.chainID = chainID
        self.scanInSignal = scanInSignal
        self.scanOutSignal = scanOutSignal
        self.elementOutputNetIDs = elementOutputNetIDs
        self.loadBits = loadBits
        self.expectedUnloadBits = expectedUnloadBits
    }
}
