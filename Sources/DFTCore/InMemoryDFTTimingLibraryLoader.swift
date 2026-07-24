import CircuiteFoundation
import TimingCore

public struct InMemoryDFTTimingLibraryLoader: DFTTimingLibraryLoading {
    public let library: TimingLibrary

    public init(library: TimingLibrary) {
        self.library = library
    }

    public func load(_ reference: ArtifactReference) throws -> TimingLibrary {
        _ = reference
        return library
    }
}
