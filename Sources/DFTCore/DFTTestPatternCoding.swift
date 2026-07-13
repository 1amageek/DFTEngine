import Foundation

public protocol DFTTestPatternCoding: Sendable {
    func encode(
        _ patternSet: DFTTestPatternSet,
        format: DFTTestPatternFormat
    ) throws -> Data

    func decode(
        _ data: Data,
        format: DFTTestPatternFormat
    ) throws -> DFTTestPatternSet
}
