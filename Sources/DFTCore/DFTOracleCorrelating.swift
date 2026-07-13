import Foundation

public protocol DFTOracleCorrelating: Sendable {
    func correlate(
        corpus: DFTOracleCorpus,
        observations: [DFTOracleCaseObservation]
    ) async throws -> DFTOracleCorrelationResult
}
