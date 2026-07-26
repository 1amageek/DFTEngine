import Foundation

public struct DFTCellLibraryManifest: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var processID: String
    public var version: String
    public var pdkDigest: String
    public var bindings: [DFTCellLibraryBinding]
    public var scanCompressionMapping: DFTScanCompressionCellMapping?
    public var evidenceProvenance: DFTEvidenceProvenance

    public init(
        processID: String,
        version: String,
        pdkDigest: String,
        bindings: [DFTCellLibraryBinding],
        scanCompressionMapping: DFTScanCompressionCellMapping? = nil,
        evidenceProvenance: DFTEvidenceProvenance,
        schemaVersion: Int = DFTCellLibraryManifest.currentSchemaVersion
    ) {
        self.schemaVersion = schemaVersion
        self.processID = processID
        self.version = version
        self.pdkDigest = pdkDigest
        self.bindings = bindings
        self.scanCompressionMapping = scanCompressionMapping
        self.evidenceProvenance = evidenceProvenance
    }
}
