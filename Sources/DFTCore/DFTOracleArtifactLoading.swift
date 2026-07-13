import Foundation
import XcircuitePackage

public protocol DFTOracleArtifactLoading: Sendable {
    func load(_ reference: XcircuiteFileReference) async throws -> Data
}
