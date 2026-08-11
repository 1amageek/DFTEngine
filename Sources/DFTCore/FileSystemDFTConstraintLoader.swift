import CircuiteFoundation
import CircuiteFoundationCrypto
import Foundation
import TimingCore

public struct FileSystemDFTConstraintLoader: DFTConstraintLoading {
    public let artifactReader: any DFTArtifactReading

    public init(artifactReader: any DFTArtifactReading) {
        self.artifactReader = artifactReader
    }

    public func load(
        _ reference: DFTConstraintReference,
        bindings: [DFTArtifactBinding]
    ) async throws -> [TimingConstraintSet] {
        var constraints: [TimingConstraintSet] = []
        for mode in reference.modes {
            let binding = try DFTArtifactBinding.require(mode.artifact, in: bindings)
            constraints.append(try await load(mode, binding: binding))
        }
        return constraints
    }

    private func load(
        _ mode: DFTConstraintModeReference,
        binding: DFTArtifactBinding
    ) async throws -> TimingConstraintSet {
        let path = binding.materializationDescription
        guard mode.artifact.descriptor.format == .sdc else {
            throw DFTConstraintError.invalidPath(path)
        }
        let data: Data
        do {
            data = try await DFTArtifactDataLoader.load(
                reference: mode.artifact,
                binding: binding,
                reader: artifactReader
            )
        } catch {
            throw DFTConstraintError.readFailed(error.localizedDescription)
        }
        return try SDCParser().parse(data, modeID: mode.modeID)
    }
}
