import Foundation

struct DFTProjectArtifactResolver: Sendable {
    let resolvedRootURL: URL

    init(rootURL: URL) {
        resolvedRootURL = rootURL.standardizedFileURL.resolvingSymlinksInPath()
    }

    func resolve(_ path: String) throws -> URL {
        let components = path.split(
            separator: "/",
            omittingEmptySubsequences: false
        )
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.hasPrefix("~"),
              !path.contains("\\"),
              !path.unicodeScalars.contains(
                where: CharacterSet.controlCharacters.contains
              ),
              !components.contains(where: {
                  $0.isEmpty || $0 == "." || $0 == ".."
              }) else {
            throw DFTProjectArtifactPathError.invalid(path)
        }
        let candidate = resolvedRootURL
            .appending(path: path)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let rootPath = resolvedRootURL.path.hasSuffix("/")
            ? resolvedRootURL.path
            : resolvedRootURL.path + "/"
        guard candidate.path == resolvedRootURL.path
                || candidate.path.hasPrefix(rootPath) else {
            throw DFTProjectArtifactPathError.invalid(path)
        }
        return candidate
    }
}
