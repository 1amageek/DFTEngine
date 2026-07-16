import DFTCore
import Foundation
import ToolQualification

public struct ExternalMemoryBISTAdapter: BISTExecuting {
    public let executor: DFTExternalToolExecutor
    private let trustDecision: ToolTrustDecision

    public init(
        runner: any DFTExternalToolRunning,
        trustDecision: ToolTrustDecision,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.executor = DFTExternalToolExecutor(runner: runner, artifactStore: artifactStore)
        self.trustDecision = trustDecision
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        guard request.operation == .bist else {
            throw DFTMemoryBISTAdapterError.operationMismatch
        }
        guard let configuration = request.bistConfiguration,
              configuration.kind == .memory else {
            throw DFTMemoryBISTAdapterError.configurationMissing
        }
        guard configuration.memoryBindings?.isEmpty == false,
              configuration.memoryBindings?.allSatisfy(\.isStructurallyComplete) == true else {
            throw DFTMemoryBISTAdapterError.bindingsMissing
        }
        let implementationID = executor.runner.descriptor.implementationID
        guard trustDecision.status == .eligible,
              trustDecision.toolID == implementationID else {
            throw DFTMemoryBISTAdapterError.toolTrustRejected(implementationID)
        }
        let result = try await executor.execute(request)
        guard result.status == .completed else {
            throw DFTMemoryBISTAdapterError.resultNotCompleted(result.status)
        }
        return result
    }
}
