# DFTEngine Design

## Purpose

Scan, ATPG and built-in self-test transformation contracts.

## Responsibility boundary

This package owns the schemas and engine protocols listed in its public products. It must remain usable without UI state and without the Xcircuite runtime.

## Non-responsibilities

- Functional synthesis
- Physical scan-chain routing
- ATE release packaging

## Dependency direction

```text
standard artifacts / canonical references
                 ↓
DFTEngine protocols and result schemas
                 ↓
native or external-tool backends
                 ↓
Xcircuite stage integration
                 ↓
DesignFlowKernel and .xcircuite artifacts
```

Backends may depend on lower-level data packages. This package must never import `Xcircuite` or `circuit-studio`.

Native backends load and identity-check canonical design, PDK, cell-library,
timing, mode-specific constraint and logic-BIST mapping artifacts through
specialized protocols. Scan and logic-BIST engines transform the canonical
`LogicDesignSnapshot`, validate the resulting graph and persist a new immutable
snapshot. `DFTResultSemanticVerifier` independently reopens the source and
output artifacts before a completed mutation crosses a flow or release
boundary. Functional equivalence, physical legality, external-oracle
correlation and process qualification remain separate gates. Unsupported or
unavailable semantics produce `blocked`; they are never converted into passing
coverage.

## Trust model

Kernel availability, corpus validation, oracle correlation, process-scoped qualification and release approval are distinct states. The package reports capability and evidence; Xcircuite and ToolQualification apply flow policy.

External DFT engines validate request/result identity, operation-specific
preconditions, process exit status, executable digest before and after
execution, and raw completion status. Completed mutation results use the same
artifact-backed semantic verifier as native engines. External integration does
not import ToolQualification or apply release policy.

## Artifact requirements

All outputs are immutable run artifacts with format, digest, producer metadata and the input design/PDK revision needed to reproduce the result.

DFT engines return the domain-owned `DFTResult` directly through the Foundation
`Engine` protocol. `DFTResult` directly provides artifacts, evidence, and
diagnostics. Artifact stores are idempotent for byte-identical writes and reject
conflicting replacements.
