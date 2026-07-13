# DFTEngine Interface Contract

## Common shape

```swift
public protocol DomainExecuting: Engine
where Request == DomainRequest,
      Output == DFTResult {}
```

Requests carry a schema version, run ID and Foundation artifact references. Payloads contain domain metrics only. Diagnostics and artifacts belong to the domain-owned `DFTResult`.

## Products

### DFTCore

Shared DFT request and result contract.

`DFTEngineExecuting` refines `CircuiteFoundation.Engine` for the domain
result. `DFTFoundationEvidence` is the explicit CircuiteFoundation evidence
view. `DFTFoundationEngine` executes the same domain protocol directly.

### ScanInsertion

Scan architecture and insertion.

### ATPGEngine

Pattern generation and fault coverage.

Process-specific fault semantics are injected through `DFTProcessFaultModeling`. `DFTATPGConfiguration.supportedProcessFamilies` declares allowed families only; it does not provide semantics. An injected model must return a `DFTProcessFaultModelResult`, which the engine validates for model identity, reason and pattern width before producing coverage. The resulting `DFTFaultOutcome.modelID` preserves the model identity in the coverage artifact.

### BISTEngine

Memory and logic BIST.

### DFTEngine

Umbrella API.

## CircuiteFoundation boundary

DFTEngine uses Foundation `ArtifactReference`, `ArtifactLocator`, `ArtifactKind`,
`ArtifactFormat`, `DesignDiagnostic` projections and `Engine` directly. The
projection preserves domain artifact IDs and rejects missing digest, byte-count,
location or diagnostic-code metadata. It never creates a random identity for an
artifact that arrived without one.


## Error contract

- Throw only when execution cannot produce a valid DFT result.
- Represent design findings and failed checks as typed diagnostics and a completed domain payload.
- Represent missing prerequisites or insufficient semantics as `blocked`.
- Preserve cancellation as `cancelled`.
- Do not swallow parser, process or persistence failures.

## Flow integration

The owning flow package resolves locators, verifies Foundation artifact
integrity, evaluates ToolQualification requirements, invokes `DFTEngineExecuting`
and persists the returned `DFTResult`. Approval and resume remain flow
responsibilities.
