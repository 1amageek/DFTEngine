import DFTCore
import Foundation

public struct ExternalMemoryBISTAdapter: BISTExecuting {
    public let executor: DFTExternalToolExecutor

    public init(
        runner: any DFTExternalToolRunning,
        artifactStore: (any DFTArtifactStoring)? = nil
    ) {
        self.executor = DFTExternalToolExecutor(runner: runner, artifactStore: artifactStore)
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
        let result = try await executor.execute(request)
        guard result.status == .completed else {
            throw DFTMemoryBISTAdapterError.resultNotCompleted(result.status)
        }
        guard result.payload.qualification.status == .processQualified else {
            throw DFTMemoryBISTAdapterError.qualificationInsufficient(
                result.payload.qualification.status
            )
        }
        return result
    }
}
