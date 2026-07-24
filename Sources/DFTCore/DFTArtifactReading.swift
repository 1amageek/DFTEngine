import CircuiteFoundation
import Foundation

public protocol DFTArtifactReading: Sendable {
    func data(for reference: ArtifactReference) async throws -> Data
}
