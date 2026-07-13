import Foundation
import DFTCore

public protocol ScanPlanning: Sendable {
    func plan(_ architecture: DFTScanArchitecture) throws -> DFTScanPlan
}
