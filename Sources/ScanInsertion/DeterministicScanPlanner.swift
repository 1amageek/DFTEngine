import Foundation
import DFTCore

public struct DeterministicScanPlanner: ScanPlanning {
    public init() {}

    public func plan(_ architecture: DFTScanArchitecture) throws -> DFTScanPlan {
        guard !architecture.domains.isEmpty else {
            throw DFTScanPlanningError.invalidDomain("at least one scan domain is required")
        }

        var chains: [DFTScanChain] = []
        var totalElementCount = 0
        for domain in architecture.domains.sorted(by: { $0.id < $1.id }) {
            guard domain.chainCount > 0, domain.estimatedElementCount > 0 else {
                throw DFTScanPlanningError.invalidDomain(
                    "domain \(domain.id) must have positive chain and element counts"
                )
            }
            let baseLength = domain.estimatedElementCount / domain.chainCount
            let remainder = domain.estimatedElementCount % domain.chainCount
            for index in 0..<domain.chainCount {
                let length = baseLength + (index < remainder ? 1 : 0)
                if let maximum = domain.maximumChainLength, length > maximum {
                    throw DFTScanPlanningError.maximumChainLengthExceeded(
                        domainID: domain.id,
                        actual: length,
                        maximum: maximum
                    )
                }
                chains.append(DFTScanChain(
                    id: "\(domain.id).chain\(index + 1)",
                    domainID: domain.id,
                    index: index,
                    estimatedElementCount: length,
                    scanInSignal: "\(architecture.scanInPrefix)_\(domain.id)_\(index + 1)",
                    scanOutSignal: "\(architecture.scanOutPrefix)_\(domain.id)_\(index + 1)"
                ))
            }
            totalElementCount += domain.estimatedElementCount
        }

        return DFTScanPlan(
            architecture: architecture,
            chains: chains,
            totalEstimatedElementCount: totalElementCount,
            maximumEstimatedChainLength: chains.map(\.estimatedElementCount).max() ?? 0
        )
    }
}
