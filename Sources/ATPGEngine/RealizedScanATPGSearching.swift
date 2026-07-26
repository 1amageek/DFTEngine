import DFTCore
import LogicIR

public protocol RealizedScanATPGSearching: Sendable {
    func search(
        snapshot: LogicDesignSnapshot,
        faults: [DFTFault],
        configuration: DFTATPGConfiguration,
        architecture: DFTScanArchitecture?,
        implementation: DFTScanImplementation,
        implementationDigest: String,
        sequentialSimulator: any GateLevelSequentialSimulating
    ) throws -> RealizedScanATPGSearchResult
}
