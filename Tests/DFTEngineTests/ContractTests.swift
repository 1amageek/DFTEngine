import Testing
import CircuiteFoundation
@testable import DFTCore
@testable import ScanInsertion
@testable import ATPGEngine
@testable import BISTEngine
@testable import DFTEngine

@Suite("DFTEngine contract")
struct ContractTests {
    @Test("contract version starts at one")
    func contractVersion() {
        #expect(DFTEngineAPI.contractVersion == 1)
    }

}
