import CircuiteFoundation
import TimingCore

public protocol DFTTimingLibraryLoading: Sendable {
    func load(_ reference: ArtifactReference) throws -> TimingLibrary
}
