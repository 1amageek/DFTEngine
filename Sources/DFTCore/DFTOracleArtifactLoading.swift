import CircuiteFoundation
import Foundation

public protocol DFTOracleArtifactLoading: Sendable {
    func load(_ reference: ArtifactReference) async throws -> Data
}
