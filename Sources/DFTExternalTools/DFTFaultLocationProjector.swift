import Foundation

struct DFTFaultLocationProjector: Sendable {
    func dutRelativePath(
        for canonicalLocation: String,
        topModule: String
    ) throws -> String {
        let topPrefix = topModule + "."
        guard canonicalLocation.hasPrefix(topPrefix) else {
            return canonicalLocation
        }
        let relativePath = String(canonicalLocation.dropFirst(topPrefix.count))
        guard !relativePath.isEmpty else {
            throw DFTScanPatternReplayError.invalidRequest(
                "fault location must identify a signal below the top module"
            )
        }
        return relativePath
    }
}
