import LogicIR

struct DFTDesignSnapshotValidator: Sendable {
    func validate(
        _ snapshot: LogicDesignSnapshot,
        for reference: LogicDesignReference
    ) throws {
        guard let gate = snapshot.gate else {
            throw DFTDesignLoaderError.gateDesignMissing
        }
        let actualDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        guard actualDigest == reference.designDigest else {
            throw DFTDesignLoaderError.designDigestMismatch(
                expected: reference.designDigest,
                actual: actualDigest
            )
        }
        guard gate.topModuleName == reference.topDesignName else {
            throw DFTDesignLoaderError.topDesignMismatch(
                expected: reference.topDesignName,
                actual: gate.topModuleName
            )
        }
        let validation = LogicDesignValidator().validate(gate)
        guard validation.isValid else {
            throw DFTDesignLoaderError.gateDesignInvalid(
                validation.diagnostics.map(\.message)
            )
        }
    }
}
