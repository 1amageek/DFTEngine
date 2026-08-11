import CircuiteFoundation
import TimingCore

public struct InMemoryDFTTimingLibraryLoader: DFTTimingLibraryLoading {
    public let library: TimingLibrary

    public init(library: TimingLibrary) {
        self.library = library
    }

    public func load(
        _ reference: ArtifactReference,
        binding: DFTArtifactBinding
    ) async throws -> TimingLibrary {
        guard binding.reference == reference else {
            throw DFTArtifactBindingError.availabilityIdentityMismatch
        }
        return library
    }
}
