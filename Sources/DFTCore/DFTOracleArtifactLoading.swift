import Foundation

public protocol DFTOracleArtifactLoading: Sendable {
    func load(_ reference: DFTArtifactReference) async throws -> Data
}
