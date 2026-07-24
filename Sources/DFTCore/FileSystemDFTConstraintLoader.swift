import CircuiteFoundation
import Foundation
import TimingCore

public struct FileSystemDFTConstraintLoader: DFTConstraintLoading {
    public let rootURL: URL

    public init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
    }

    public func load(_ reference: DFTConstraintReference) throws -> [TimingConstraintSet] {
        try reference.modes.map { mode in
            try load(mode)
        }
    }

    private func load(
        _ mode: DFTConstraintModeReference
    ) throws -> TimingConstraintSet {
        let path = mode.artifact.path
        guard mode.artifact.format == .sdc else {
            throw DFTConstraintError.invalidPath(path)
        }
        let url: URL
        do {
            url = try DFTProjectArtifactResolver(rootURL: rootURL).resolve(path)
        } catch {
            throw DFTConstraintError.invalidPath(path)
        }
        let data: Data
        do {
            data = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            throw DFTConstraintError.readFailed(error.localizedDescription)
        }
        guard UInt64(data.count) == mode.artifact.byteCount,
              try SHA256ContentDigester().digest(data: data) == mode.artifact.digest else {
            throw DFTConstraintError.identityMismatch(path)
        }
        return try SDCParser().parse(data, modeID: mode.modeID)
    }
}
