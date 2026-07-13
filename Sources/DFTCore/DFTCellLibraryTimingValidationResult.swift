import Foundation

public struct DFTCellLibraryTimingValidationResult: Sendable, Hashable, Codable {
    public var processID: String
    public var pdkDigest: String
    public var validatedBindingIDs: [String]
    public var timingCellNames: [String]
    public var legalReplacementGroups: [String]
    public var clockToQBindingCount: Int

    public init(
        processID: String,
        pdkDigest: String,
        validatedBindingIDs: [String],
        timingCellNames: [String],
        legalReplacementGroups: [String],
        clockToQBindingCount: Int
    ) {
        self.processID = processID
        self.pdkDigest = pdkDigest
        self.validatedBindingIDs = validatedBindingIDs
        self.timingCellNames = timingCellNames
        self.legalReplacementGroups = legalReplacementGroups
        self.clockToQBindingCount = clockToQBindingCount
    }
}
