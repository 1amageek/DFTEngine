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

`DFTEngineExecuting` refines `CircuiteFoundation.Engine` for the domain result.
`DefaultDFTEngine` conforms directly, and `DFTResult` directly provides the
CircuiteFoundation artifact, evidence, and diagnostic contracts.

`DFTConstraintReference` contains one immutable artifact per declared mode.
`DFTConstraintLoading` parses each mode independently; engines require an
injected loader and never skip validation. `DFTResultValidator` checks the
closed typed result, while `DFTResultSemanticVerifier` reopens immutable design
and mapping artifacts to validate completed mutations at integration
boundaries.

### ScanInsertion

Scan architecture and insertion.

### ATPGEngine

Pattern generation and fault coverage.

Process-specific fault semantics are injected through `DFTProcessFaultModeling`. `DFTATPGConfiguration.supportedProcessFamilies` declares allowed families only; it does not provide semantics. An injected model must return a `DFTProcessFaultModelResult`, which the engine validates for model identity, reason and pattern width before producing coverage. The resulting `DFTFaultOutcome.modelID` preserves the model identity in the coverage artifact.

### BISTEngine

Memory and logic BIST.

Logic BIST consumes `DFTLogicBISTCellMappingLoading`; the decoded artifact must
exactly match the process/PDK-bound inline mapping contract. Memory BIST retains
exact macro bindings and remains an external execution boundary.

`ExternalMemoryBISTEngine` validates the memory-BIST operation, complete macro
bindings, the shared external-result identity contract, completed status, and
artifact-backed semantic evidence. External descriptors identify the resolved
executable by SHA-256 rather than an engine label.
It does not import ToolQualification or decide whether a tool is trusted.

### DFTPatternExchange

Rich standard-pattern interchange semantics.

`DFTPatternExchangeProgram` contains ordered signals, signal groups, timing
sets, waveform symbols and events, procedures, cycles, assignments, and pattern
calls. `DFTPatternExchangeValidator` requires exact references, complete
per-cycle signal coverage, legal drive/compare direction, and in-period ordered
events. `STILPatternCodec` encodes and decodes only the accepted STIL subset.
Unknown constructs, unsupported time units, invalid text, malformed groups, and
semantic loss are typed failures.
`DFTStandardPatternCoding.capability` declares the exact standard version,
ASCII encoding, picosecond unit, waveform actions, structural sections, and
escaped-identifier support accepted by a codec.

This product does not change `DFTTestPatternSet`, execute ATPG, invoke a replay
tool, or make qualification decisions.

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
responsibilities. `DFTEvidenceProvenance` is raw observation metadata and never
constitutes a qualification or release decision.

`DFTDesignDiff` carries raw structural changes and snapshot references only.
DesignFlowKernel owns review state and approval transitions. Release evidence
composition is provided by the composing flow and is not evaluated by
DFTEngine.
