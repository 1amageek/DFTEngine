public protocol DFTScanImplementationValidating: Sendable {
    func validationIssues(
        in implementation: DFTScanImplementation
    ) -> [DFTScanImplementationValidationIssue]
}
