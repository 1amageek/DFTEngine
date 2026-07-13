import DFTCore
import LogicIR

public protocol DFTFaultExtracting: Sendable {
    func extract(
        from snapshot: LogicDesignSnapshot,
        reference: LogicDesignReference
    ) throws -> DFTFaultUniverse
}
