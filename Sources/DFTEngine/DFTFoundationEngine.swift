import CircuiteFoundation
import DFTCore
import Foundation

/// Foundation-native execution seam for the DFT domain.
public protocol DFTFoundationExecuting: Engine
where Request == DFTRequest, Output == DFTFoundationEvidence {}

/// Adapts the retained DFT result envelope to the shared Foundation evidence
/// contract while preserving the legacy payload for domain-specific callers.
public struct DFTFoundationEngine: DFTFoundationExecuting {
    public let legacyEngine: any DFTEngineExecuting

    public init(legacyEngine: any DFTEngineExecuting) {
        self.legacyEngine = legacyEngine
    }

    public func execute(_ request: DFTRequest) async throws -> DFTFoundationEvidence {
        let result = try await legacyEngine.execute(request)
        let metadata = result.metadata
        let producer = try ProducerIdentity(
            kind: .engine,
            identifier: metadata.engineID,
            version: metadata.implementationVersion,
            build: metadata.implementationID
        )
        let inputs = try request.inputs.map(DFTFoundationEvidence.artifactReference(from:))
        let provenance = try ExecutionProvenance(
            producer: producer,
            inputs: inputs,
            configurationDigest: try DFTFoundationEngine.configurationDigest(for: request),
            designRevision: try DFTFoundationEngine.sha256Digest(
                request.design.designDigest
            ),
            randomSeed: metadata.seed,
            startedAt: metadata.startedAt,
            completedAt: metadata.completedAt
        )
        return try DFTFoundationEvidence(result: result, provenance: provenance)
    }

    private static func configurationDigest(
        for request: DFTRequest
    ) throws -> ContentDigest {
        let hexadecimalValue = try DFTDeterministicHasher().digest(request)
        return try ContentDigest(
            algorithm: .sha256,
            hexadecimalValue: hexadecimalValue
        )
    }

    private static func sha256Digest(_ value: String) throws -> ContentDigest {
        try ContentDigest(algorithm: .sha256, hexadecimalValue: value)
    }
}
