public protocol DFTCLIOutputWriting: Sendable {
    func writeOutput(_ value: String)
    func writeError(_ value: String)
}
