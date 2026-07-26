import Foundation

public struct DFTScanCompressionCellMapping: Sendable, Hashable, Codable {
    public var decompressorCellType: String
    public var compactorCellType: String
    public var decompressorInputPinNames: [String]
    public var decompressorOutputPinNames: [String]
    public var compactorInputPinNames: [String]
    public var compactorOutputPinNames: [String]

    public init(
        decompressorCellType: String,
        compactorCellType: String,
        decompressorInputPinNames: [String],
        decompressorOutputPinNames: [String],
        compactorInputPinNames: [String],
        compactorOutputPinNames: [String]
    ) {
        self.decompressorCellType = decompressorCellType
        self.compactorCellType = compactorCellType
        self.decompressorInputPinNames = decompressorInputPinNames
        self.decompressorOutputPinNames = decompressorOutputPinNames
        self.compactorInputPinNames = compactorInputPinNames
        self.compactorOutputPinNames = compactorOutputPinNames
    }
}
