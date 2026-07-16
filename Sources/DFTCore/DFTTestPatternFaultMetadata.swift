import Foundation

public struct DFTTestPatternFaultMetadata: Sendable, Hashable, Codable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var faultIDsByPatternID: [String: [String]]

    public init(patterns: [DFTTestPattern]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.faultIDsByPatternID = Dictionary(
            uniqueKeysWithValues: patterns.map { ($0.id, $0.faultIDs) }
        )
    }

    public func validatedFaultIDs(patternIDs: [String]) throws -> [String: [String]] {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw DFTPatternFormatError.malformedPattern("fault metadata schema version is unsupported")
        }
        guard Set(faultIDsByPatternID.keys) == Set(patternIDs) else {
            throw DFTPatternFormatError.malformedPattern("fault metadata must cover every pattern exactly once")
        }
        for (patternID, faultIDs) in faultIDsByPatternID {
            guard faultIDs.allSatisfy({ !$0.isEmpty }), Set(faultIDs).count == faultIDs.count else {
                throw DFTPatternFormatError.malformedPattern(
                    "fault metadata for pattern \(patternID) contains an empty or duplicate fault ID"
                )
            }
        }
        return faultIDsByPatternID
    }
}
