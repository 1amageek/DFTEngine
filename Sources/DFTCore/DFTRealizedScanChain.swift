import Foundation

public struct DFTRealizedScanChain: Sendable, Hashable, Codable {
    public var chainID: String
    public var domainID: String
    public var scanInSignal: String
    public var scanInNetID: String
    public var scanOutSignal: String
    public var scanOutNetID: String
    public var elements: [DFTScanElementBinding]

    public init(
        chainID: String,
        domainID: String,
        scanInSignal: String,
        scanInNetID: String,
        scanOutSignal: String,
        scanOutNetID: String,
        elements: [DFTScanElementBinding]
    ) {
        self.chainID = chainID
        self.domainID = domainID
        self.scanInSignal = scanInSignal
        self.scanInNetID = scanInNetID
        self.scanOutSignal = scanOutSignal
        self.scanOutNetID = scanOutNetID
        self.elements = elements
    }
}
