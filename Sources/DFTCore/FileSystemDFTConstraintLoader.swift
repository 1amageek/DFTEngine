import CircuiteFoundation
import Foundation
import TimingCore

public struct FileSystemDFTConstraintLoader: DFTConstraintLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: DFTConstraintReference) throws -> [TimingConstraintSet] {
        let path = reference.artifact.path
        guard reference.artifact.format == .sdc,
              !path.isEmpty,
              !path.hasPrefix("/"),
              !path.split(separator: "/").contains("..") else {
            throw DFTConstraintError.invalidPath(path)
        }
        let url = rootURL.appendingPathComponent(path).standardizedFileURL
        guard url.path == rootURL.path || url.path.hasPrefix(rootURL.path + "/") else {
            throw DFTConstraintError.invalidPath(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DFTConstraintError.readFailed(error.localizedDescription)
        }
        guard UInt64(data.count) == reference.artifact.byteCount,
              try SHA256ContentDigester().digest(data: data) == reference.artifact.digest else {
            throw DFTConstraintError.identityMismatch(path)
        }
        return try reference.modeIDs.map { modeID in
            try SDCParser().parse(data, modeID: modeID)
        }
    }
}
