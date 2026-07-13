# DFTEngine Interface Contract

## Common shape

```swift
public protocol DomainExecuting: Engine
where Request == DomainRequest,
      Output == XcircuiteEngineResultEnvelope<DomainPayload> {}
```

Requests carry a schema version, run ID and typed artifact references. Payloads contain domain metrics only. Diagnostics and artifacts belong to the shared envelope.

## Products

### DFTCore

Shared DFT request and result contract.

`DFTEngineExecuting` refines `CircuiteFoundation.Engine` for the domain
envelope. `DFTFoundationEvidence` is the explicit CircuiteFoundation
projection. `DFTFoundationEngine` adapts any `DFTEngineExecuting`
implementation to `Engine<DFTRequest, DFTFoundationEvidence>` and records
verified request inputs in `ExecutionProvenance`.

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

DFTEngine keeps the existing Xcircuite request/result envelope for the current
runtime, but exposes `DFTFoundationEvidence` as the shared boundary. The
projection preserves domain artifact IDs and rejects missing digest,
byte-count, location or diagnostic-code metadata. It never creates a random
identity for an artifact that arrived without one.


## Error contract

- Throw only when execution cannot produce a valid result envelope.
- Represent design findings and failed checks as typed diagnostics and a completed domain payload.
- Represent missing prerequisites or insufficient semantics as `blocked`.
- Preserve cancellation as `cancelled`.
- Do not swallow parser, process or persistence failures.

## Xcircuite adapter

The adapter must:

1. resolve project-relative references through XcircuitePackage;
2. verify input digests;
3. evaluate ToolQualification requirements;
4. invoke the injected engine protocol;
5. persist every returned artifact;
6. map diagnostics and status to FlowStageResult;
7. attach design, PDK and tool provenance;
8. leave approval and resume handling to DesignFlowKernel.
