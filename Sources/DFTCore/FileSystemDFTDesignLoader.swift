import Foundation
import LogicIR
import XcircuitePackage

public struct FileSystemDFTDesignLoader: DFTDesignLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: LogicDesignReference) throws -> LogicDesignSnapshot {
        guard reference.artifact.format == .json else {
            throw DFTDesignLoaderError.unsupportedFormat(reference.artifact.format)
        }
        let url = try resolve(reference.artifact.path)
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DFTDesignLoaderError.readFailed(
                path: reference.artifact.path,
                message: error.localizedDescription
            )
        }
        if let expectedByteCount = reference.artifact.byteCount,
           expectedByteCount != Int64(data.count) {
            throw DFTDesignLoaderError.byteCountMismatch(
                path: reference.artifact.path,
                expected: expectedByteCount,
                actual: Int64(data.count)
            )
        }
        if let expectedDigest = reference.artifact.sha256 {
            let actualDigest = XcircuiteHasher().sha256(data: data)
            guard expectedDigest == actualDigest else {
                throw DFTDesignLoaderError.artifactDigestMismatch(
                    path: reference.artifact.path,
                    expected: expectedDigest,
                    actual: actualDigest
                )
            }
        }

        let snapshot: LogicDesignSnapshot
        do {
            snapshot = try LogicDesignSnapshotCodec.decode(data)
        } catch {
            throw DFTDesignLoaderError.snapshotDecodeFailed(
                path: reference.artifact.path,
                message: error.localizedDescription
            )
        }
        try validate(snapshot: snapshot, reference: reference)
        return snapshot
    }

    private func resolve(_ path: String) throws -> URL {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            throw DFTDesignLoaderError.invalidPath(path)
        }
        let url = rootURL.appendingPathComponent(path).standardizedFileURL
        guard url.path == rootURL.path || url.path.hasPrefix(rootURL.path + "/") else {
            throw DFTDesignLoaderError.invalidPath(path)
        }
        return url
    }

    private func validate(
        snapshot: LogicDesignSnapshot,
        reference: LogicDesignReference
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
            let message = validation.diagnostics.map(\.message).joined(separator: "; ")
            throw DFTDesignLoaderError.snapshotDecodeFailed(
                path: reference.artifact.path,
                message: "Gate design validation failed: \(message)"
            )
        }
    }
}
