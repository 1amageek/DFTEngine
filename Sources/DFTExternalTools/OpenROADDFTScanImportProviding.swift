public protocol OpenROADDFTScanImportProviding: Sendable {
    func importScan(
        _ request: OpenROADDFTScanImportRequest
    ) async throws -> OpenROADDFTScanImportResult
}
