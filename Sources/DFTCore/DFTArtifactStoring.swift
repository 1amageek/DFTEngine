import CircuiteFoundation
import Foundation

public protocol DFTArtifactStoring: Sendable {
    func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> ArtifactReference
}
