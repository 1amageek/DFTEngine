# DFTEngine Milestones

DFTEngine is a semiconductor design-platform component, not a pattern generator demo. Each milestone must leave a reproducible artifact, a structured failure path and a developer-facing regression test. A capability is not considered complete merely because a type or external engine exists.

## Milestone map

| ID | Scope | Completion gate | Status |
|---|---|---|---|
| M0 | Contract and evidence baseline | Versioned request/result, immutable artifacts, blocked/cancelled states, deterministic CLI and retained fixtures | Complete |
| M1 | Canonical gate-level scan transformation | Load and digest-verify `LogicDesignSnapshot`, transform real `GateDesign`, validate transformed IR, persist snapshot and design diff | Complete for the current LogicIR contract |
| M2 | Scan architecture semantics | Infer or explicitly bind clock/reset domains, identify sequential cell semantics, reject ambiguous library mappings, preserve functional/test-mode connectivity | In progress: process-scoped manifest, exact pin/net binding and Liberty timing/legal replacement validator delivered; process qualification remains |
| M3 | Gate-level ATPG | Generate faults from transformed gate IR, implement sensitization/propagation for a declared supported cell subset, validate patterns by simulation, never claim unsupported coverage | In progress: exhaustive combinational stuck-at, bounded DFF/SDFF SI/SE scan-shift/capture, explicit reset/set control contracts, qualified level-sensitive latch semantics and bounded combinational/sequential transition slices delivered; process-specific faults now require an injected model boundary and validated model result; unknown primitives and process qualification remain |
| M4 | BIST insertion | Insert controller, pattern source, response compactor and test-mode isolation into canonical IR; memory macros require an explicit backend protocol | In progress: canonical logic-BIST transform, typed memory-macro binding and external backend protocol delivered; backend completion requires process-qualified evidence and native memory transformation remains blocked |
| M5 | Standard pattern and external execution | Qualified STIL/WGL import/export, process execution timeout/cancellation/tree cleanup, stdout/stderr and tool result artifacts | In progress: internal interchange codec, timed process runner, stdout/stderr artifacts and Xcircuite persistence of validated typed DFT results delivered; native STIL/WGL output and process/tool qualification remain blocked |
| M6 | Evidence emission and trust handoff | Retained corpus, reference-oracle correlation, PDK-scoped observations and request-digest-bound provenance | In progress: artifact-integrity-checked correlation and `DFTEvidenceProvenance` emission are delivered; independent process corpus remains |
| M7 | Platform flow composition | Direct protocol consumption, ToolQualification trust evaluation, Xcircuite review/approval/resume, and equivalence/DRC/LVS/PEX handoff | Outside the domain package: DFTEngine supplies typed results and raw evidence; ToolQualification and the composing flow own the policy |
| M8 | Production signoff and tapeout handoff | Accepted process/tool evidence, independent oracle record, real DFT/equivalence/DRC/LVS/PEX artifacts, human approval and immutable release manifest | Outside DFTEngine and incomplete at the platform level |

## Current M1 boundary

M1 performs a real structural transformation of the canonical gate snapshot. It preserves functional cells and ports, adds scan controls and chain connectivity, binds scan outputs directly through canonical port/net bindings, and emits a new digest-addressed snapshot plus a reviewable diff. No synthetic observability cell is inserted.

M1 does not claim:

- clock/reset inference from Liberty or a PDK cell library;
- functional equivalence proof;
- physical scan routing or DFT rule signoff;
- ATPG coverage or ATE release readiness.

## M2 current slice

The transformer requires a process-scoped cell-library manifest and a digest-verified Liberty/canonical timing artifact. It binds each functional sequential cell to an exact scan-cell mapping and pin contract, validates D/Q/clock semantics, required pins, clock-to-Q timing and legal replacement groups, checks reset/clock connectivity, and verifies per-domain element counts before chain assignment. Missing or mismatched timing evidence blocks execution.

## M3 current slice

`GateLevelFaultExtractor` derives two stuck-at faults per driven top-level gate net from the canonical `GateDesign`. `GateLevelCombinationalSimulator` evaluates a deliberately bounded primitive subset (`AND`, `NAND`, `OR`, `NOR`, `XOR`, `XNOR`, `NOT`/`INV` and `BUF`) and compares good/faulty observable outputs over exhaustive primary-input assignments. For explicitly supported DFF and SDFF cells, `GateLevelSequentialSimulator` adds bounded clock-edge/state-transition simulation over multi-cycle input sequences and selects `SI` over `D` when `SE` is asserted, so scan shift and functional capture are represented structurally. `DFTSequentialCellContract` now carries reset/set pin names, active polarity, synchronous/asynchronous timing, active clock edge, level-sensitive element kind and latch-enable polarity; missing or conflicting controls are typed failures. `GateLevelTransitionSimulator` supports explicitly directed slow-to-rise/slow-to-fall faults over bounded launch/capture vectors for combinational and qualified sequential designs. Unknown primitives, missing connectivity and unobservable faults block coverage rather than being counted as detected. The extracted universe, patterns, outcomes and assumptions are persisted through the existing artifact envelope.

Process-specific faults use the protocol-first `DFTProcessFaultModeling` boundary: `supportedProcessFamilies` is only a declaration, while detection requires an injected model, model identity/result validation and a binary pattern of the configured width. A model result is not process qualification; independent oracle and ToolQualification evidence remain required for release.

## M4 current slice

Logic BIST requires exact target bindings plus a process/PDK-bound mapping for controller, mux, capture, compactor and signature cells, PRPG/MISR polynomial taps and expected signature. The mapping is retained in the result. Memory BIST has a typed macro boundary, but a completed external result without transformed evidence is rejected.

## M5-M6 current slices

JSON is the native ATPG output. STIL/WGL requests and scan compression fail closed until qualified implementations exist. `DFTExternalTools` owns the `SignoffToolSupport` timed process adapter; `DFTCore` owns only the typed runner/result contracts. Every external backend must report stdout, stderr and exit code, and all results pass the same exact-input and completed-payload validator.

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
