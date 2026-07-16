# DFTEngine Goal Status

## Current state

**M0 and M1 are complete. M2 has process-scoped binding plus a Liberty timing/legal-cell validator. M3 has combinational stuck-at, bounded DFF/SDFF state-transition, explicit reset/set polarity/timing/edge contracts, level-sensitive latch semantics, bounded sequential transition-fault simulation, and an injected model boundary for process-specific faults. M4 has canonical logic-BIST plus a typed memory backend protocol. M5-M6 provide reusable artifacts, oracle correlation, and request-digest-bound evidence provenance. DFTEngine emits observations only; ToolQualification owns implementation trust and the composing flow owns downstream policy, approval, resume, and release.**

| Maturity gate | Status | Evidence |
|---|---|---|
| Responsibility boundary | Complete | README.md and DESIGN.md |
| Public package products | Complete | Package.swift |
| Canonical Foundation and domain request/result contract | Complete | Versioned request, payload and typed domain result |
| Contract build | Complete | `swift build` |
| Contract test | Complete | Timeout-bounded `DFTEngine-Package` Xcode test through the workspace verifier |
| Domain implementation | M2/M3/M4 partial | Gate-level scan transformation, process-scoped cell binding, Liberty timing/legal validation, combinational and bounded sequential ATPG including explicit reset/set and latch semantics, process-specific model injection boundary, standard pattern codecs and canonical logic-BIST transformation are validated; native memory BIST remains bounded |
| CLI implementation | Complete | `dft-engine capabilities` and `execute` with strict option validation and deterministic JSON output |
| Fixture corpus | Retained | Positive scan and negative ATPG fixtures |
| Oracle correlation | Correlation infrastructure available; process qualification not claimed | Retained expectation artifact integrity, native-result correlation and deterministic evidence digest are implemented; no independent process oracle is bundled |
| Process qualification | Not claimed | PDK/macro-specific evidence is external policy |
| Xcircuite stage composition | Direct protocol boundary | Xcircuite invokes DFT protocols and persists returned artifacts; it combines ToolQualification decisions and downstream evidence under flow-owned policy |
| End-to-end flow evidence | External composition responsibility | DFTEngine supplies typed results, request-bound provenance, and correlation observations; the composing flow owns cross-engine validation |
| Release readiness | External policy | Requires accepted process/tool evidence, real equivalence/DRC/LVS/PEX artifacts, review approval, and immutable flow records |

## Function status

| Function | Contract | Implementation | Validation corpus | Qualification |
|---|---|---|---|---|
| Fault model | Implemented | Deterministic family and universe validation | Fixture coverage | Smoke checked |
| Scan architecture | Implemented | Deterministic chain planner | Positive fixture | Smoke checked |
| Scan insertion | Implemented | Digest-verified canonical snapshot transformation, explicit clock/reset binding, validator pass and design diff | DFTEngine tests + CLI fixture | Unqualified helper/library mapping |
| ATPG | Partial implementation | Declared-fault backend plus extracted combinational stuck-at, bounded DFF/SDFF scan-shift/capture, explicit reset/set and level-sensitive latch semantics, bounded sequential/combinational transition backends, and protocol-first process-specific model injection with result validation | Positive/negative gate-level tests, including undeclared-family, missing-model and injected-model paths | Smoke checked; retained oracle correlation is available but no process corpus is bundled |
| BIST | Partial implementation | Canonical logic gate transformation with test-mode mux/capture/compactor; memory macro path requires an external backend conforming to the published protocol and a process-qualified result | Positive transformed-snapshot and backend-gate tests | Smoke checked; helper cells and macro legality unqualified |
| Pattern formats | M5 partial | JSON, strict STIL and strict WGL codec with lossless fault-ID metadata; timed external process runner | Vector and fault-ID round-trip plus malformed-input tests | Smoke checked |
| Coverage evidence | Implemented | Universe digest, outcomes and assumptions | ATPG tests and oracle correlation tests | No process qualification |

## Foundation migration boundary

`DFTFoundationEvidence` and `DFTFoundationEngine` are the explicit CircuiteFoundation boundary. The conforming implementation preserves verified request inputs, configuration digest, design revision, producer identity, seed, output artifacts and diagnostics while returning the typed DFT result directly. In-memory and actor-isolated file-system artifact stores are immutable and idempotent for byte-identical writes; conflicting replacements and symlink escapes are rejected.

## Goal progression

```text
contract scaffold
      ↓
deterministic contract implementation
      ↓
canonical gate-level transformation (M1)
      ↓
process-scoped scan-cell binding (M2 slice)
      ↓
combinational gate-level ATPG semantics (M3 slice)
      ↓
declared sequential control and transition semantics (M3 slice)
      ↓
explicit process-specific fault-model boundary (M3 trust gate)
      ↓
canonical logic-BIST transformation (M4 slice)
      ↓
strict standard-pattern and timed external execution (M5 slice)
      ↓
reference-oracle correlation and evidence provenance (M6 slice)
      ↓
ToolQualification trust evaluation (external)
      ↓
DesignFlowKernel/Xcircuite review, approval, resume, and release policy
      ↓
```

## Completion definition

The package is complete only for its declared execution and evidence-emission
scope. Platform production readiness remains external and requires retained
corpus/oracle artifacts, accepted cell/macro tool evidence, downstream
equivalence/DRC/LVS/PEX evidence, and final approval.

## Current blockers

- The native gate-level ATPG covers exhaustive binary combinational simulation, bounded DFF/SDFF clock-edge/state semantics including SI/SE scan shift and functional capture, explicit reset/set polarity/timing/edge contracts, qualified level-sensitive latch semantics and bounded combinational/sequential transition semantics. Process-specific faults require an injected `DFTProcessFaultModeling` implementation and validated result; unknown primitives and process-qualified timing remain blocked.
- Native logic BIST requires explicit target pin bindings and transforms a canonical gate snapshot; controller, mux, capture and compactor helper cells still require process qualification.
- Strict STIL/WGL decoding with lossless fault-ID metadata, a timeout/tree-cleaning external runner, external stdout/stderr artifacts, and retained-oracle correlation are available; concrete flow persistence, independent process evidence, and tool promotion remain integrating-flow responsibilities.
- `DFTOracleCorrelationEngine` can verify normalized retained oracle expectation artifacts, compare native envelopes and emit a deterministic correlation digest; no real process corpus is bundled in this package.
- The current LogicIR does not encode process-qualified scan-capture/reset semantics; M2 timing/legal bindings and explicit architecture contracts must block ambiguous designs.
- M2 uses an explicit process-scoped manifest, exact net/pin binding and a Liberty timing/legal replacement validator; process-qualified timing evidence and legal replacement approval remain external.
- `DFT_SCAN_OUT` is an intermediate structural helper and requires a process-qualified cell mapping before physical signoff.
- Full Xcircuite release readiness remains external to this package; real accepted downstream evidence is still required.
- An external tool runner is injected through `DFTExternalToolRunning`; a concrete vendor command must be selected and qualified by the integrating project.
- Process-specific fault semantics and memory macro legality require PDK-scoped evidence outside this package.

This file must be updated by implementation agents whenever a maturity gate changes. A source file or type name alone is never evidence of implementation or qualification.
