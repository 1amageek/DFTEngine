import Foundation

public protocol DFTStandardPatternCoding: Sendable {
    var capability: DFTStandardPatternCapability { get }

    func encode(_ program: DFTPatternExchangeProgram) throws -> Data
    func decode(_ data: Data) throws -> DFTPatternExchangeProgram
}
