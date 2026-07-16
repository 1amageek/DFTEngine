import Foundation
import ATPGEngine
import BISTEngine
import DFTCore
import ScanInsertion

public enum DFTEngineAPI {
    public static let contractVersion = 1

    public static func defaultEngine(
        artifactStore: (any DFTArtifactStoring)? = nil,
        designLoader: (any DFTDesignLoading)? = nil,
        cellLibraryLoader: (any DFTCellLibraryLoading)? = nil
    ) -> DefaultDFTEngine {
        if let artifactStore, let designLoader, let cellLibraryLoader {
            return DefaultDFTEngine(
                artifactStore: artifactStore,
                designLoader: designLoader,
                cellLibraryLoader: cellLibraryLoader
            )
        }
        if let artifactStore, let designLoader {
            return DefaultDFTEngine(
                artifactStore: artifactStore,
                designLoader: designLoader
            )
        }
        if let artifactStore {
            return DefaultDFTEngine(artifactStore: artifactStore)
        }
        if let designLoader {
            return DefaultDFTEngine(
                scanInsertion: DeterministicScanInsertionEngine(designLoader: designLoader),
                atpg: DeterministicATPGEngine(designLoader: designLoader),
                bist: DeterministicBISTEngine(designLoader: designLoader)
            )
        }
        return DefaultDFTEngine()
    }

}
