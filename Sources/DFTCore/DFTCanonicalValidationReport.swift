public struct DFTCanonicalValidationReport: Sendable, Hashable {
    public let findings: [DFTCanonicalValidationFinding]

    public init(findings: [DFTCanonicalValidationFinding]) {
        self.findings = findings
    }

    public var isValid: Bool { findings.isEmpty }
}
