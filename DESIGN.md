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
timing, mode-specific constraint, logic-BIST mapping, and memory-BIST mapping
artifacts through specialized protocols. Scan, scan-compression, logic-BIST,
and memory-BIST engines transform the canonical `LogicDesignSnapshot`, validate
the resulting graph and persist a new immutable snapshot.
`DFTResultSemanticVerifier` independently reopens the source and output
artifacts before a completed mutation crosses a flow or release boundary.
Functional equivalence, physical legality, external-oracle correlation and
process qualification remain separate gates. Unsupported or unavailable
semantics produce `blocked`; they are never converted into passing coverage.

Scan-compression architecture owns topology and external channel names.
Process-specific decompressor/compactor cell and pin identities belong to the
cell-library manifest. The transformer composes the two contracts without
embedding process names in the architecture layer.

Memory-BIST orchestration is separate from the logic-BIST transformer. It
consumes explicit macro port bindings plus a process-bound helper mapping,
validates the macro set and clock-domain legality, and emits canonical helper
connectivity. Standard-pattern formatting remains a format-provider
responsibility. The compact coverage IR does not carry STIL/WGL timing and
procedure semantics, while `DFTScanPatternExecutionPlan` is the
standard-neutral contract for exact realized-scan execution.

The accepted production provider keeps that responsibility in
`DFTPatternExchange`. The target owns conversion from
`DFTScanPatternExecutionPlan`, the rich model, exact validation, and the
fail-closed STIL subset codec. ATPG owns generation of that neutral plan from a
digest-verified `DFTScanImplementation`; it does not own STIL syntax. The scan
implementation is distinct from `DFTScanPlan`: the plan owns architecture
intent and estimated counts, while the implementation owns exact transformed
design identity, ordered cells, and pin/net bindings. Native semantic
verification replays exact load/capture/compare/unload behavior before
completion. Retained STIL bytes then enter an independent Icarus replay path.
The replay path derives injection locations from a retained fault universe,
checks them against a retained realized-scan contract, and emits raw
observations without importing trust policy. OpenROAD scan insertion, Yosys
functional-mode equivalence, hosted replay qualification, and
ToolQualification remain separate evidence producers. See
`docs/adr/0001-production-dft-provider.md`.

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
