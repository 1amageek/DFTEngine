# DFTEngine Implementation Plan

## Order and implementation status

The full platform goal is intentionally decomposed into the gates documented in `MILESTONES.md`.

1. M0 contract and evidence baseline — complete
2. M1 canonical gate-level scan transformation — complete for the current LogicIR contract
3. M2 scan clock/reset and cell-library semantics — in progress; explicit gate connectivity and Liberty timing/legal replacement validation slices delivered
4. M3 gate-level ATPG and pattern validation — combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set controls, qualified level-sensitive latch semantics, bounded combinational/sequential transition slices and an injected process-specific fault-model boundary delivered; unknown primitives and process qualification remain
5. M4 canonical BIST insertion — logic target transformation, typed memory-macro backend protocol and process-qualified external-result gate delivered; native qualified memory backend remains
6. M5 strict standard-pattern and external-tool execution — strict codec, timed/tree-cleaning process runner, stdout/stderr artifacts and typed DFT result persistence delivered; process/tool qualification remains
7. M6 retained corpus and oracle correlation — raw correlation and evidence-provenance emission are delivered; independent retained process corpus remains
8. M7 ToolQualification and flow handoff — direct DFT protocol consumption and raw evidence handoff are delivered; trust, downstream signoff policy, approval, and resume remain responsibilities of ToolQualification and the composing flow
9. M8 production signoff and tapeout handoff — outside DFTEngine; the composing flow requires accepted tool/process evidence, independent oracle records, real DFT/equivalence/DRC/LVS/PEX artifacts, and human approval

## Delivered implementation slice

- Implemented versioned request/result contracts, immutable artifact stores, deterministic CLI and structured blocked/cancelled states.
- Completed direct CircuiteFoundation conformance through `DFTEngineExecuting`, `DefaultDFTEngine`, and `DFTResult`; verified inputs, configuration digest, design revision, seed, and producer identity are retained in shared provenance.
- Enforced immutable artifact-store writes, stable artifact IDs, safe request/reference paths and strict external-tool implementation identity/version matching.
- Added canonical `LogicDesignSnapshot` loading with project-root bounds, byte-count and SHA-256 checks, design-digest verification, top-design checks and gate validation.
- Added a real gate-level scan transformation that updates sequential cells, control ports, scan nets, chain observability helpers and stable design diffs.
- Added explicit clock/reset connectivity binding and per-domain element-count checks; ambiguous bindings are blocked.
- Recomputed and validated the transformed snapshot digest before persistence.
- Added positive/negative fixtures and an explicit regression that scan insertion blocks without a canonical design loader.
- Added headless Xcircuite composition; its production path invokes the DFT protocols directly and injects a project-rooted filesystem design loader.
- Added process-scoped scan-cell binding manifests with artifact and PDK digest verification.
- Added gate-level stuck-at fault extraction and exhaustive binary simulation for a bounded combinational primitive subset; unsupported sequential semantics block coverage.
- Added bounded DFF/SDFF SI/SE scan-shift and functional-capture simulation, reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded sequential transition-fault simulation; unknown primitives and process-qualified timing remain explicitly blocked.
- Added the protocol-first `DFTProcessFaultModeling` boundary for process-specific ATPG. A declared process family alone cannot produce coverage; the engine requires an injected model, matching model identity, a non-empty reason and a binary pattern with the configured width, with typed blocked diagnostics for missing, unsupported, failed or malformed model results.
- Added canonical logic-BIST transformation with explicit target pin bindings, test-mode input muxing, response capture/compaction, signature output and immutable design diff.
- Tightened JSON/STIL/WGL pattern validation and added a `SignoffToolSupport`-backed external process runner with timeout, cancellation and process-tree cleanup.
- Added raw DFT evidence maturity and provenance metadata for smoke, corpus, and
  oracle-correlated observations without embedding a trust or release verdict.
- Added retained oracle corpus contracts and correlation: normalized oracle expectation artifacts are read, byte-count/digest verified, decoded and compared against native typed results before correlation evidence is emitted.
- Added a Liberty-backed scan-cell timing/legal replacement validator requiring scan pins, sequential D/Q/clock semantics, clock-to-Q timing and a legal replacement group.
- Added a typed memory-macro BIST binding and external backend protocol; non-completed or non-process-qualified external results are rejected, and native memory transformation remains blocked until a qualified backend is supplied.
- Preserved request digests in evidence provenance so ToolQualification and flow
  policy can bind observations to the exact DFT execution.
- Defined the integration boundary: the composing runtime persists typed DFT
  results and combines them with downstream equivalence/DRC/LVS/PEX evidence;
  DesignFlowKernel owns approval and resume.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- DFTEngine emits raw evidence and never claims foundry qualification or release
  eligibility.
- Xcircuite can execute and persist a DFT stage without circuit-studio; the
  composing flow consumes its artifacts through direct protocols.
- Production signoff remains outside DFTEngine until the selected
  process/toolchain and downstream engines supply independent evidence.
