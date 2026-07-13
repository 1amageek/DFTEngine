import Foundation

public protocol DFTExecutionRequest: Sendable, Hashable, Codable {
    var schemaVersion: Int { get }
    var runID: String { get }
    var inputs: [DFTArtifactReference] { get }
}
