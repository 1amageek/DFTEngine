# DFTEngine Implementation Plan

## Order and implementation status

The full platform goal is intentionally decomposed into the gates documented in `MILESTONES.md`.

1. M0 contract and evidence baseline — complete
2. M1 canonical gate-level scan transformation — complete for the current LogicIR contract
3. M2 scan clock/reset and cell-library semantics — in progress; explicit gate connectivity and Liberty timing/legal replacement validation slices delivered
4. M3 gate-level ATPG and pattern validation — combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set controls, qualified level-sensitive latch semantics, bounded combinational/sequential transition slices and an injected process-specific fault-model boundary delivered; unknown primitives and process qualification remain
5. M4 canonical BIST insertion — logic target transformation, typed memory-macro adapter boundary and process-qualified external-result gate delivered; native qualified memory backend remains
6. M5 strict standard-pattern and external-tool execution — strict codec, timed/tree-cleaning process runner, stdout/stderr artifacts and Xcircuite result-envelope persistence delivered; process/tool qualification remains
7. M6 retained corpus, oracle correlation and process qualification — promotion gate, artifact-backed ToolQualification evidence builder/CLI and Xcircuite qualification stage complete; independent retained process corpus remains
8. M7 Xcircuite approval/resume and release loop — DFT release eligibility, request-digest-bound qualification provenance, mandatory ToolQualification process evidence, four-domain downstream evidence bundle, generic approval/resume integration, self-contained support references and release-manifest integrity verification delivered; production downstream evidence remains
9. M8 production signoff and tapeout handoff — not complete; requires actual process-qualified cell/macro evidence, independent oracle record, real DFT/equivalence/DRC/LVS/PEX artifacts and human approval

## Delivered implementation slice

- Implemented versioned request/result contracts, immutable artifact stores, deterministic CLI and structured blocked/cancelled states.
- Completed the CircuiteFoundation execution boundary with `DFTFoundationEvidence` and `DFTFoundationEngine`; verified inputs, configuration digest, design revision, seed and producer identity are retained in shared provenance.
- Enforced immutable artifact-store writes, stable artifact IDs, safe request/reference paths and strict external-tool implementation identity/version matching.
- Added canonical `LogicDesignSnapshot` loading with project-root bounds, byte-count and SHA-256 checks, design-digest verification, top-design checks and gate validation.
- Added a real gate-level scan transformation that updates sequential cells, control ports, scan nets, chain observability helpers and stable design diffs.
- Added explicit clock/reset connectivity binding and per-domain element-count checks; ambiguous bindings are blocked.
- Recomputed and validated the transformed snapshot digest before persistence.
- Added positive/negative fixtures and an explicit regression that scan insertion blocks without a canonical design loader.
- Added the headless Xcircuite adapter; its production path injects a project-rooted filesystem design loader.
- Added process-scoped scan-cell binding manifests with artifact and PDK digest verification.
- Added gate-level stuck-at fault extraction and exhaustive binary simulation for a bounded combinational primitive subset; unsupported sequential semantics block coverage.
- Added bounded DFF/SDFF SI/SE scan-shift and functional-capture simulation, reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded sequential transition-fault simulation; unknown primitives and process-qualified timing remain explicitly blocked.
- Added the protocol-first `DFTProcessFaultModeling` boundary for process-specific ATPG. A declared process family alone cannot produce coverage; the engine requires an injected model, matching model identity, a non-empty reason and a binary pattern with the configured width, with typed blocked diagnostics for missing, unsupported, failed or malformed model results.
- Added canonical logic-BIST transformation with explicit target pin bindings, test-mode input muxing, response capture/compaction, signature output and immutable design diff.
- Tightened JSON/STIL/WGL pattern validation and added a `SignoffToolSupport`-backed external process runner with timeout, cancellation and process-tree cleanup.
- Added a qualification promotion gate that requires complete corpus pass, process/PDK identity, oracle evidence digest, retained artifact metadata and approval.
- Added an artifact-backed ToolQualification process-evidence builder and `toolqualification build-process-evidence` CLI. It validates independent scoped corpus/oracle/health/approval evidence, exact artifact coverage, SHA-256/byte counts and a current expiry window before emitting a qualified record; blocked input never writes a result.
- Added retained oracle corpus contracts and correlation: normalized oracle expectation artifacts are read, byte-count/digest verified, decoded and compared against native result envelopes before qualification evidence can be created.
- Added a Liberty-backed scan-cell timing/legal replacement validator requiring scan pins, sequential D/Q/clock semantics, clock-to-Q timing and a legal replacement group.
- Added a typed memory-macro BIST binding and external adapter boundary; non-completed or non-process-qualified external results are rejected, and native memory transformation remains blocked until a qualified backend is supplied.
- Added a DFT release eligibility gate requiring process qualification, complete DFT artifacts, ATPG coverage where applicable, equivalence/DRC/LVS/PEX evidence and explicit human approval.
- Added request-digest-bound qualification provenance so a release cannot consume process evidence from a different DFT request.
- Added a protocol-first Xcircuite validator for ToolProcessQualificationEvidence; every DFT release now validates freshness, independence, corpus/oracle/health/approval evidence IDs, tool/implementation identity, process profile and PDK digest, then retains the evidence as a required immutable release artifact.
- Added an Xcircuite downstream evidence bundle stage that resolves, hashes and persists exactly one equivalence, DRC, LVS and PEX artifact for the release gate.
- Added Xcircuite DFT result-envelope persistence, release-time SHA-256/byte-count verification for DFT and downstream artifacts, an immutable eligibility artifact and a blocked review/resume artifact with stable run and design-digest identity.
- Added a stage-bound qualification process-evidence input. The qualification stage verifies the declared support artifacts, builds the independent evidence record, persists it as a release artifact and retains the build request plus support artifacts so the release packet is self-contained. The release stage re-verifies every named manifest reference before persisting the immutable packet.
- Integrated the DFT-specific blocked result with the generic Xcircuite approval recorder and resumer; resume re-enters the release gate and cannot bypass DFT eligibility evaluation.

## Completion gates

- Public APIs remain protocol-first and Sendable.
- Every unsupported semantic produces a structured blocked result.
- Native and external backends produce the same result schema.
- No UI type enters a public contract.
- No result claims foundry qualification without process-scoped oracle evidence.
- Xcircuite can execute and persist the M2 scan stage without circuit-studio; the composed qualification → independent process evidence → downstream evidence bundle → approval/resume → DFT release flow consumes persisted artifacts, verifies request and artifact identity, and emits either an immutable eligibility artifact or a review/resume contract.
- M8 remains open until the selected process/toolchain supplies independently generated qualification and signoff artifacts; fixture evidence cannot promote itself to production qualification.
