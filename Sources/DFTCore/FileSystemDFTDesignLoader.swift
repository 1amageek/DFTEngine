import CircuiteFoundation
import Foundation
import LogicIR

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
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTDesignLoaderError.readFailed(
                path: reference.artifact.path,
                message: error.localizedDescription
            )
        }
        let actualByteCount = Int64(data.count)
        guard actualByteCount == Int64(reference.artifact.byteCount) else {
            throw DFTDesignLoaderError.byteCountMismatch(
                path: reference.artifact.path,
                expected: Int64(reference.artifact.byteCount),
                actual: actualByteCount
            )
        }
        let actualArtifactDigest = try SHA256ContentDigester().digest(data: data)
        guard actualArtifactDigest == reference.artifact.digest else {
            throw DFTDesignLoaderError.artifactDigestMismatch(
                path: reference.artifact.path,
                expected: reference.artifact.digest.hexadecimalValue,
                actual: actualArtifactDigest.hexadecimalValue
            )
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
        try DFTDesignSnapshotValidator().validate(snapshot, for: reference)
        return snapshot
    }

    private func resolve(_ path: String) throws -> URL {
        do {
            return try DFTProjectArtifactResolver(rootURL: rootURL).resolve(path)
        } catch {
            throw DFTDesignLoaderError.invalidPath(path)
        }
    }

}
