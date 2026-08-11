import LogicIR

public protocol DFTDesignLoading: Sendable {
    func load(
        _ reference: LogicDesignReference,
        binding: DFTArtifactBinding
    ) async throws -> LogicDesignSnapshot
}
