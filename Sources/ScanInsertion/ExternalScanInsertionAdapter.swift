import DFTCore
import Foundation
import XcircuitePackage

public struct ExternalScanInsertionAdapter: ScanInserting {
    public let executor: DFTExternalToolExecutor

    public init(
        runner: any DFTExternalToolRunning,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.executor = DFTExternalToolExecutor(runner: runner, artifactStore: artifactStore)
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> XcircuiteEngineResultEnvelope<DFTPayload> {
        try await executor.execute(request)
    }
}
