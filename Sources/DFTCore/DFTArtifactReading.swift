import CircuiteFoundation
import Foundation

public protocol DFTArtifactReading: Sendable {
    func data(for binding: DFTArtifactBinding) async throws -> Data
}
