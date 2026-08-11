import CircuiteFoundation
import Foundation

public protocol DFTOracleArtifactLoading: Sendable {
    func load(_ binding: DFTArtifactBinding) async throws -> Data
}
