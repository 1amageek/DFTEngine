import DFTCore

public protocol DFTRealizedScanATPGRequestBuilding: Sendable {
    func build(
        importResult: OpenROADDFTScanImportResult,
        configuration: DFTRealizedScanATPGRequestConfiguration
    ) async throws -> DFTRequest
}
