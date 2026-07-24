import ATPGEngine
import BISTEngine
import DFTCore
import Foundation
import ScanInsertion

public struct DefaultDFTEngine: DFTEngineExecuting {
    public let scanInsertion: any ScanInserting
    public let atpg: any ATPGExecuting
    public let bist: any BISTExecuting

    public init(
        scanInsertion: any ScanInserting = DeterministicScanInsertionEngine(),
        atpg: any ATPGExecuting = DeterministicATPGEngine(),
        bist: any BISTExecuting = DeterministicBISTEngine()
    ) {
        self.scanInsertion = scanInsertion
        self.atpg = atpg
        self.bist = bist
    }

    public init(artifactStore: any DFTArtifactStoring) {
        self.init(
            scanInsertion: DeterministicScanInsertionEngine(artifactStore: artifactStore),
            atpg: DeterministicATPGEngine(artifactStore: artifactStore),
            bist: DeterministicBISTEngine(artifactStore: artifactStore)
        )
    }

    public init(designLoader: any DFTDesignLoading) {
        self.init(
            scanInsertion: DeterministicScanInsertionEngine(designLoader: designLoader),
            atpg: DeterministicATPGEngine(designLoader: designLoader),
            bist: DeterministicBISTEngine(designLoader: designLoader)
        )
    }

    public init(
        artifactStore: any DFTArtifactStoring,
        designLoader: any DFTDesignLoading,
        cellLibraryLoader: any DFTCellLibraryLoading,
        timingLibraryLoader: any DFTTimingLibraryLoading,
        constraintLoader: any DFTConstraintLoading,
        logicBISTCellMappingLoader: any DFTLogicBISTCellMappingLoading =
            UnavailableDFTLogicBISTCellMappingLoader()
    ) {
        self.init(
            scanInsertion: DeterministicScanInsertionEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                cellLibraryLoader: cellLibraryLoader,
                timingLibraryLoader: timingLibraryLoader,
                constraintLoader: constraintLoader
            ),
            atpg: DeterministicATPGEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                cellLibraryLoader: cellLibraryLoader,
                timingLibraryLoader: timingLibraryLoader,
                constraintLoader: constraintLoader
            ),
            bist: DeterministicBISTEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                constraintLoader: constraintLoader,
                logicBISTCellMappingLoader: logicBISTCellMappingLoader
            )
        )
    }

    public init(
        artifactStore: any DFTArtifactStoring,
        designLoader: any DFTDesignLoading
    ) {
        self.init(
            scanInsertion: DeterministicScanInsertionEngine(
                artifactStore: artifactStore,
                designLoader: designLoader
            ),
            atpg: DeterministicATPGEngine(
                artifactStore: artifactStore,
                designLoader: designLoader
            ),
            bist: DeterministicBISTEngine(
                artifactStore: artifactStore,
                designLoader: designLoader
            )
        )
    }

    public func execute(
        _ request: DFTRequest
    ) async throws -> DFTResult {
        switch request.operation {
        case .scanInsertion:
            return try await scanInsertion.execute(request)
        case .atpg:
            return try await atpg.execute(request)
        case .bist:
            return try await bist.execute(request)
        }
    }

    public var capabilityReport: DFTCapabilityReport {
        DFTCapabilityReport(
            engineID: "dft",
            implementationID: "default-router",
            implementationVersion: DFTExecutionSupport.implementationVersion,
            capabilities: [
                "scan_insertion": .available,
                "atpg": .available,
                "bist": .available,
                "operation_routing": .available
            ],
            limitations: [
                "Domain evidence maturity is reported by the selected backend and is not upgraded by routing."
            ],
            evidenceProvenance: evidenceProvenance
        )
    }

    private var evidenceProvenance: DFTEvidenceProvenance {
        DFTEvidenceProvenance(
            status: .smokeObserved,
            notes: ["umbrella router delegates without changing domain evidence"]
        )
    }
}
