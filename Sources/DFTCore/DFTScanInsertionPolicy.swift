import Foundation

public struct DFTScanInsertionPolicy: Sendable, Hashable, Codable {
    public var scanCellName: String
    public var preserveFunctionalPorts: Bool
    public var requireTestMode: Bool
    public var generateDesignDiff: Bool
    public var allowUnknownCells: Bool

    public init(
        scanCellName: String,
        preserveFunctionalPorts: Bool = true,
        requireTestMode: Bool = true,
        generateDesignDiff: Bool = true,
        allowUnknownCells: Bool = false
    ) {
        self.scanCellName = scanCellName
        self.preserveFunctionalPorts = preserveFunctionalPorts
        self.requireTestMode = requireTestMode
        self.generateDesignDiff = generateDesignDiff
        self.allowUnknownCells = allowUnknownCells
    }
}
