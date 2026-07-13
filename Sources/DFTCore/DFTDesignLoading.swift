import LogicIR

public protocol DFTDesignLoading: Sendable {
    func load(_ reference: LogicDesignReference) throws -> LogicDesignSnapshot
}
