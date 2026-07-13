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

    public init(
        artifactStore: any DFTArtifactStoring,
        designLoader: any DFTDesignLoading,
        cellLibraryLoader: any DFTCellLibraryLoading
    ) {
        self.init(
            scanInsertion: DeterministicScanInsertionEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                cellLibraryLoader: cellLibraryLoader
            ),
            atpg: DeterministicATPGEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                cellLibraryLoader: cellLibraryLoader
            ),
            bist: DeterministicBISTEngine(
                artifactStore: artifactStore,
                designLoader: designLoader
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
        guard let operation = request.operation else {
            return DFTExecutionSupport.result(
                request: request,
                engineID: "dft",
                implementationID: "default-router",
                status: .blocked,
                diagnostics: [
                    DFTDiagnostic(
                        severity: .error,
                        code: "DFT_OPERATION_MISSING",
                        message: "The umbrella DFT engine requires an explicit operation.",
                        entity: "operation",
                        suggestedActions: ["select_scan_insertion_atpg_or_bist"]
                    )
                ],
                payload: DFTPayload(
                    transformedDesign: nil,
                    faultCoverage: nil,
                    qualification: qualification,
                    assumptions: ["no domain executor was selected"]
                ),
                startedAt: Date()
            )
        }
        switch operation {
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
                "Domain-specific qualification is reported by the selected backend and is not upgraded by routing."
            ],
            qualification: qualification
        )
    }

    private var qualification: DFTQualificationProvenance {
        DFTQualificationProvenance(
            status: .smokeChecked,
            notes: ["umbrella router delegates without changing domain evidence"]
        )
    }
}
