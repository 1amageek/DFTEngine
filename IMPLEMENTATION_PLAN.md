# DFTEngine Implementation Plan

## Order and implementation status

The full platform goal is intentionally decomposed into the gates documented in `MILESTONES.md`.

1. M0 contract and evidence baseline — complete
2. M1 canonical gate-level scan transformation — complete for the current LogicIR contract
3. M2 scan clock/reset, cell-library, and compression semantics — native structural scope complete; process qualification remains external
4. M3 gate-level ATPG and pattern validation — combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set controls, qualified level-sensitive latch semantics, bounded combinational/sequential transition slices and an injected process-specific fault-model boundary delivered; unknown primitives and process qualification remain
5. M4 canonical BIST insertion — native logic and memory target transformations plus the typed external boundary are delivered; process qualification remains flow-owned
6. M5 standard-pattern and external-tool execution — internal codec, timed/tree-cleaning process runner, stdout/stderr artifacts and validated typed DFT result persistence delivered; qualified native STIL/WGL output and process/tool qualification remain
7. M6 retained corpus and oracle correlation — raw correlation and evidence-provenance emission are delivered; independent retained process corpus remains
8. M7 ToolQualification and flow handoff — direct DFT protocol consumption and raw evidence handoff are delivered; trust, downstream signoff policy, approval, and resume remain responsibilities of ToolQualification and the composing flow
9. M8 production signoff and tapeout handoff — outside DFTEngine; the composing flow requires accepted tool/process evidence, independent oracle records, real DFT/equivalence/DRC/LVS/PEX artifacts, and human approval

## Delivered implementation slice

- Implemented versioned request/result contracts, immutable artifact stores, deterministic CLI and structured blocked/cancelled states.
- Completed direct CircuiteFoundation conformance through `DFTEngineExecuting`, `DefaultDFTEngine`, and `DFTResult`; verified inputs, configuration digest, design revision, seed, and producer identity are retained in shared provenance.
- Enforced immutable artifact-store writes, stable artifact IDs, safe request/reference paths and strict external-tool engine/version plus executable SHA-256 matching.
- Added one digest-bound constraint artifact per mode, mandatory constraint
  loading, exact mode-set validation, clock/test-mode/scan-enable checks, and
  conflicting case-analysis rejection.
- Enforced the PDK reference's manifest identity before dispatch instead of
  treating the inline process metadata as sufficient.
- Added canonical `LogicDesignSnapshot` loading with project-root bounds, byte-count and SHA-256 checks, design-digest verification, top-design checks and gate validation.
- Added a real gate-level scan transformation that updates sequential cells, control ports, scan nets, canonical port/net bindings and stable design diffs without synthetic observability cells.
- Added scan-compression transformation with architecture-owned channel
  topology and process-manifest-owned decompressor/compactor cell and pin
  mappings. Exact internal-chain and external-channel coverage is validated,
  and the hot path uses indexed net lookup plus linear chain-offset tracking.
- Added explicit clock/reset connectivity binding and per-domain element-count checks; ambiguous bindings are blocked.
- Recomputed and validated the transformed snapshot digest before persistence.
- Added positive/negative fixtures and an explicit regression that scan insertion blocks without a canonical design loader.
- Added headless Xcircuite composition; its production path invokes the DFT protocols directly and injects a project-rooted filesystem design loader.
- Added process-scoped scan-cell binding manifests with artifact and PDK digest verification.
- Added gate-level stuck-at fault extraction and exhaustive binary simulation for a bounded combinational primitive subset; unsupported sequential semantics block coverage.
- Added bounded DFF/SDFF SI/SE scan-shift and functional-capture simulation, reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded sequential transition-fault simulation; unknown primitives and process-qualified timing remain explicitly blocked.
- Added protocol-first `DFTProcessFaultModeling` generation and `DFTProcessFaultPatternVerifying` validation boundaries for process-specific ATPG. A declared process family alone cannot produce coverage; detected outcomes require distinct model/verifier identities, a verified binary pattern, and capture timing bound to a declared DFT clock. The same contract is enforced for external completed results, with typed blocked diagnostics for missing, unsupported, failed, rejected, or malformed evidence.
- Added canonical logic-BIST transformation with explicit target pin bindings,
  test-mode input muxing, response capture/compaction, signature output,
  immutable design diff, and a separately loaded process/PDK-bound helper-cell
  mapping artifact.
- Added canonical memory-BIST transformation with exact target/macro binding,
  process/PDK-bound helper mapping bytes, algorithm and macro capability
  checks, single-domain clock validation, explicit mux/controller/compactor/
  signature connectivity, immutable design diff, and structure artifacts.
- Kept JSON as the only native qualified output, blocked STIL/WGL requests until standards-qualified exporters exist, and moved the `SignoffToolSupport` process adapter into `DFTExternalTools`.
- Added raw DFT evidence maturity and provenance metadata for smoke, corpus, and
  oracle-correlated observations without embedding a trust or release verdict.
- Added retained oracle corpus contracts and correlation: normalized oracle expectation artifacts are read, byte-count/digest verified, decoded and compared against native typed results before correlation evidence is emitted.
- Connected the Liberty-backed scan-cell timing/legal replacement validator to scan insertion and process-scoped ATPG execution; missing timing artifacts now block execution.
- Retained the typed external memory-macro backend protocol; non-completed,
  identity-mismatched, or completed-without-transformation results are
  rejected, while ToolQualification remains flow-owned.
- Removed flow-owned review state from `DFTDesignDiff`; the current contract
  contains raw structural changes and snapshot references only.
- Rejected non-zero external exits before response decoding, bound external
  provenance inputs to the request, verified the executable digest before and
  after execution, and preserved Foundation evidence identity when
  stdout/stderr artifacts are attached.
- Added `DFTResultSemanticVerifier` to reopen source/transformed design and
  mapping artifacts, recheck identity and canonical validity, and reject
  unchanged or structurally inconsistent completed mutations. Xcircuite stage
  and release boundaries delegate to this verifier.
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
