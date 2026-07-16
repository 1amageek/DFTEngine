# DFTEngine Milestones

DFTEngine is a semiconductor design-platform component, not a pattern generator demo. Each milestone must leave a reproducible artifact, a structured failure path and a developer-facing regression test. A capability is not considered complete merely because a type or adapter exists.

## Milestone map

| ID | Scope | Completion gate | Status |
|---|---|---|---|
| M0 | Contract and evidence baseline | Versioned request/result, immutable artifacts, blocked/cancelled states, deterministic CLI and retained fixtures | Complete |
| M1 | Canonical gate-level scan transformation | Load and digest-verify `LogicDesignSnapshot`, transform real `GateDesign`, validate transformed IR, persist snapshot and design diff | Complete for the current LogicIR contract |
| M2 | Scan architecture semantics | Infer or explicitly bind clock/reset domains, identify sequential cell semantics, reject ambiguous library mappings, preserve functional/test-mode connectivity | In progress: process-scoped manifest, exact pin/net binding and Liberty timing/legal replacement validator delivered; process qualification remains |
| M3 | Gate-level ATPG | Generate faults from transformed gate IR, implement sensitization/propagation for a declared supported cell subset, validate patterns by simulation, never claim unsupported coverage | In progress: exhaustive combinational stuck-at, bounded DFF/SDFF SI/SE scan-shift/capture, explicit reset/set control contracts, qualified level-sensitive latch semantics and bounded combinational/sequential transition slices delivered; process-specific faults now require an injected model boundary and validated model result; unknown primitives and process qualification remain |
| M4 | BIST insertion | Insert controller, pattern source, response compactor and test-mode isolation into canonical IR; memory macros require an explicit backend protocol | In progress: canonical logic-BIST transform, typed memory-macro binding and external backend protocol delivered; backend completion requires process-qualified evidence and native memory transformation remains blocked |
| M5 | Standard pattern and external execution | Strict STIL/WGL parsing and validation, process execution timeout/cancellation/tree cleanup, stdout/stderr and tool result artifacts | In progress: strict codec, timed process runner, stdout/stderr artifacts and Xcircuite persistence of typed DFT results delivered; process/tool qualification remains |
| M6 | Evidence emission and trust handoff | Retained corpus, reference-oracle correlation, PDK-scoped observations and request-digest-bound provenance | In progress: artifact-integrity-checked correlation and `DFTEvidenceProvenance` emission are delivered; independent process corpus remains |
| M7 | Platform flow composition | Direct protocol consumption, ToolQualification trust evaluation, Xcircuite review/approval/resume, and equivalence/DRC/LVS/PEX handoff | Outside the domain package: DFTEngine supplies typed results and raw evidence; ToolQualification and the composing flow own the policy |
| M8 | Production signoff and tapeout handoff | Accepted process/tool evidence, independent oracle record, real DFT/equivalence/DRC/LVS/PEX artifacts, human approval and immutable release manifest | Outside DFTEngine and incomplete at the platform level |

## Current M1 boundary

M1 performs a real structural transformation of the canonical gate snapshot. It preserves the existing functional cells and ports, adds scan controls and chain connectivity, and emits a new digest-addressed snapshot plus a reviewable diff. The M2 connectivity slice checks domain assignment against explicit clock/reset net names; process-qualified clock arcs and legal scan-cell replacement remain open. `DFT_SCAN_OUT` is therefore an explicit intermediate helper and is not a foundry-legal standard-cell claim.

M1 does not claim:

- clock/reset inference from Liberty or a PDK cell library;
- functional equivalence proof;
- physical scan routing or DFT rule signoff;
- ATPG coverage or ATE release readiness.

## M2 current slice

The transformer now requires a process-scoped cell-library manifest, binds each functional sequential cell to an exact scan-cell mapping and pin contract, binds each sequential cell to a declared scan clock by matching the canonical gate net name, checks reset connectivity when a domain declares a reset, and verifies per-domain element counts before chain assignment. Artifact bytes, SHA-256, manifest digest, process ID, version and PDK digest are checked. A missing, ambiguous or mismatched binding is blocked with an actionable diagnostic. The timing validator checks a bound Liberty `TimingCell` for required scan/control pins, a sequential model, matching D/Q/clock semantics and a clock-to-Q arc, while requiring an explicit legal replacement group. Foundry qualification evidence remains open.

## M3 current slice

`GateLevelFaultExtractor` derives two stuck-at faults per driven top-level gate net from the canonical `GateDesign`. `GateLevelCombinationalSimulator` evaluates a deliberately bounded primitive subset (`AND`, `NAND`, `OR`, `NOR`, `XOR`, `XNOR`, `NOT`/`INV` and `BUF`) and compares good/faulty observable outputs over exhaustive primary-input assignments. For explicitly supported DFF and SDFF cells, `GateLevelSequentialSimulator` adds bounded clock-edge/state-transition simulation over multi-cycle input sequences and selects `SI` over `D` when `SE` is asserted, so scan shift and functional capture are represented structurally. `DFTSequentialCellContract` now carries reset/set pin names, active polarity, synchronous/asynchronous timing, active clock edge, level-sensitive element kind and latch-enable polarity; missing or conflicting controls are typed failures. `GateLevelTransitionSimulator` supports explicitly directed slow-to-rise/slow-to-fall faults over bounded launch/capture vectors for combinational and qualified sequential designs. Unknown primitives, missing connectivity and unobservable faults block coverage rather than being counted as detected. The extracted universe, patterns, outcomes and assumptions are persisted through the existing artifact envelope.

Process-specific faults use the protocol-first `DFTProcessFaultModeling` boundary: `supportedProcessFamilies` is only a declaration, while detection requires an injected model, model identity/result validation and a binary pattern of the configured width. A model result is not process qualification; independent oracle and ToolQualification evidence remain required for release.

## M4 current slice

Logic BIST requires explicit target instance pin bindings. The transformer adds test-mode input muxes around bound target inputs, response capture cells, a response compactor, a controller cell, a signature register and observable done/signature ports. The resulting canonical snapshot is digest-finalized and accompanied by a structural design diff. Memory BIST now has a typed macro port/algorithm binding and external backend protocol; the external path rejects non-completed or non-process-qualified typed results, while native transformation remains blocked until a macro-qualified backend is injected.

## M5-M6 current slices

JSON, STIL and WGL pattern artifacts now reject malformed metadata, duplicate IDs, inconsistent widths, non-binary vectors and incomplete containers. External execution can use the shared `SignoffToolSupport` timed process runner, which captures stdout/stderr and cleans a process tree on timeout or cancellation. Xcircuite persists the complete typed DFT result as a run artifact. `DFTOracleCorrelationEngine` verifies normalized retained oracle expectation artifacts, compares native typed results and emits a deterministic correlation digest. `DFTEvidenceProvenance` records raw evidence maturity and identity; ToolQualification performs the separate trust evaluation.

## M7 current slice

The Xcircuite release-stage composition now requires independently validated `ToolProcessQualificationEvidence`. It checks the evidence schema, freshness, independence flag, corpus/oracle/health/approval/evidence artifact IDs, tool and implementation identity, process profile and PDK digest, then includes the evidence reference in the immutable eligibility artifact. The ToolQualification builder/CLI promotes only artifact-backed, independently scoped evidence and preserves the expiry window. Missing or mismatched process evidence produces a blocked review/resume result.

DFTEngine does not expose a DFT-specific release eligibility gate or
review/resume contract. The composing flow verifies DFT and downstream files,
applies ToolQualification decisions, records human approval, and builds any
immutable release packet. Request-digest-bound `DFTEvidenceProvenance` lets that
policy prove which DFT execution produced the observations without allowing the
domain engine to self-promote them.

## Definition of done for each future milestone

```text
canonical input
    -> typed transformation
    -> validated output IR
    -> immutable artifact + digest
    -> structured diagnostics
    -> retained positive/negative regression
    -> CLI/API reproducibility
    -> Xcircuite review and resume evidence
```

The milestone is complete only when every applicable arrow has evidence. Unsupported semantics remain `blocked`; they are not promoted by the router or by a smoke test.
