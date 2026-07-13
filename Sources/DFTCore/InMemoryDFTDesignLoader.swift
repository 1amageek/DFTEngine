import LogicIR

public struct InMemoryDFTDesignLoader: DFTDesignLoading {
    public let snapshot: LogicDesignSnapshot

    public init(snapshot: LogicDesignSnapshot) {
        self.snapshot = snapshot
    }

    public func load(_ reference: LogicDesignReference) throws -> LogicDesignSnapshot {
        guard snapshot.gate != nil else {
            throw DFTDesignLoaderError.gateDesignMissing
        }
        let actualDigest = try LogicDesignSnapshotCodec.digest(snapshot)
        guard actualDigest == reference.designDigest else {
            throw DFTDesignLoaderError.designDigestMismatch(
                expected: reference.designDigest,
                actual: actualDigest
            )
        }
        guard snapshot.gate?.topModuleName == reference.topDesignName else {
            throw DFTDesignLoaderError.topDesignMismatch(
                expected: reference.topDesignName,
                actual: snapshot.gate?.topModuleName ?? ""
            )
        }
        return snapshot
    }
}
