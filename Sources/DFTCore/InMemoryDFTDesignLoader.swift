import LogicIR

public struct InMemoryDFTDesignLoader: DFTDesignLoading {
    public let snapshot: LogicDesignSnapshot

    public init(snapshot: LogicDesignSnapshot) {
        self.snapshot = snapshot
    }

    public func load(
        _ reference: LogicDesignReference,
        binding: DFTArtifactBinding
    ) async throws -> LogicDesignSnapshot {
        guard binding.reference == reference.artifact else {
            throw DFTArtifactBindingError.availabilityIdentityMismatch
        }
        try DFTDesignSnapshotValidator().validate(snapshot, for: reference)
        return snapshot
    }
}
