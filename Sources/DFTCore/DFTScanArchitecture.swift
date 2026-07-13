import Foundation

public struct DFTScanArchitecture: Sendable, Hashable, Codable {
    public var name: String
    public var clocks: [DFTScanClock]
    public var resets: [DFTScanReset]
    public var domains: [DFTScanDomain]
    public var compression: DFTCompressionConfiguration?
    public var scanEnableSignal: String
    public var testModeSignal: String
    public var scanInPrefix: String
    public var scanOutPrefix: String

    public init(
        name: String,
        clocks: [DFTScanClock],
        resets: [DFTScanReset] = [],
        domains: [DFTScanDomain],
        compression: DFTCompressionConfiguration? = nil,
        scanEnableSignal: String,
        testModeSignal: String,
        scanInPrefix: String = "scan_in",
        scanOutPrefix: String = "scan_out"
    ) {
        self.name = name
        self.clocks = clocks
        self.resets = resets
        self.domains = domains
        self.compression = compression
        self.scanEnableSignal = scanEnableSignal
        self.testModeSignal = testModeSignal
        self.scanInPrefix = scanInPrefix
        self.scanOutPrefix = scanOutPrefix
    }
}
