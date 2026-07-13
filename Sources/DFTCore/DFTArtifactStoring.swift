import Foundation
import XcircuitePackage

public protocol DFTArtifactStoring: Sendable {
    func store(
        _ content: DFTArtifactContent,
        runID: String
    ) async throws -> XcircuiteFileReference
}
