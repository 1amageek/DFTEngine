import LogicIR

public struct InMemoryDFTDesignLoader: DFTDesignLoading {
    public let snapshot: LogicDesignSnapshot

    public init(snapshot: LogicDesignSnapshot) {
        self.snapshot = snapshot
    }

    public func load(_ reference: LogicDesignReference) throws -> LogicDesignSnapshot {
        try DFTDesignSnapshotValidator().validate(snapshot, for: reference)
        return snapshot
    }
}
