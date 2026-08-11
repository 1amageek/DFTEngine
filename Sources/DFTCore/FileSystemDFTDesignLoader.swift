import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import LogicIR

public struct FileSystemDFTDesignLoader: DFTDesignLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: LogicDesignReference,
        binding: DFTArtifactBinding
    ) async throws -> LogicDesignSnapshot {
        guard reference.artifact.descriptor.format == .json else {
            throw DFTDesignLoaderError.unsupportedFormat(reference.artifact.descriptor.format)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: reference.artifact,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTDesignLoaderError.readFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        let snapshot: LogicDesignSnapshot
        do {
            snapshot = try LogicDesignSnapshotCodec.decode(data)
        } catch {
            throw DFTDesignLoaderError.snapshotDecodeFailed(
                path: binding.materializationDescription,
                message: error.localizedDescription
            )
        }
        try DFTDesignSnapshotValidator().validate(snapshot, for: reference)
        return snapshot
    }
}
