import Foundation
import TimingCore

public protocol DFTCellLibraryTimingValidating: Sendable {
    func validate(
        manifest: DFTCellLibraryManifest,
        timingLibrary: TimingLibrary
    ) throws -> DFTCellLibraryTimingValidationResult
}
