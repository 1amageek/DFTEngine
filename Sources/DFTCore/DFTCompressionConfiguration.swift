import Foundation

public struct DFTCompressionConfiguration: Sendable, Hashable, Codable {
    public var enabled: Bool
    public var ratio: Double?
    public var decompressorCell: String?
    public var compactorCell: String?

    public init(
        enabled: Bool,
        ratio: Double? = nil,
        decompressorCell: String? = nil,
        compactorCell: String? = nil
    ) {
        self.enabled = enabled
        self.ratio = ratio
        self.decompressorCell = decompressorCell
        self.compactorCell = compactorCell
    }
}
